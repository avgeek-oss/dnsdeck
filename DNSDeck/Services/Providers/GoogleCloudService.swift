import AvgeekNetworking
import Foundation
import os.log
import Security

enum GCPAPIError: Error, LocalizedError {
    case missingCredentials
    case invalidCredentials
    case http(Int)
    case googleCloud(GCPError)
    case decoding(Error)
    case jwt(Error)
    case missingProjectId

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Google Cloud credentials are missing."
        case .invalidCredentials: "Invalid Google Cloud credentials."
        case let .http(code): "HTTP error \(code)."
        case let .googleCloud(error): error.message ?? "Google Cloud API error."
        case let .decoding(e): "Decoding error: \(e.localizedDescription)."
        case let .jwt(e): "JWT creation error: \(e.localizedDescription)."
        case .missingProjectId: "Google Cloud project ID is missing."
        }
    }
}

final class GoogleCloudService {
    private let base = URL(string: Configuration.API.googleCloudBase)!
    private let domainsBase = URL(string: Configuration.API.googleCloudDomainsBase)!
    private let oauthBase = URL(string: Configuration.API.googleCloudOAuth)!
    private let credentialsProvider: () -> String?
    private let projectIdProvider: () -> String?
    private let transport: any NetworkTransport
    private let accessTokenProvider: (() async throws -> String)?

    private let tokenLock = NSLock()
    private var _cachedAccessToken: String?
    private var _tokenExpiry: Date?

    private var cachedAccessToken: String? {
        get {
            tokenLock.lock()
            defer { tokenLock.unlock() }
            return _cachedAccessToken
        }
        set {
            tokenLock.lock()
            defer { tokenLock.unlock() }
            _cachedAccessToken = newValue
        }
    }

    private var tokenExpiry: Date? {
        get {
            tokenLock.lock()
            defer { tokenLock.unlock() }
            return _tokenExpiry
        }
        set {
            tokenLock.lock()
            defer { tokenLock.unlock() }
            _tokenExpiry = newValue
        }
    }

    init(
        credentialsProvider: @escaping () -> String?,
        projectIdProvider: @escaping () -> String?,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        accessTokenProvider: (() async throws -> String)? = nil
    ) {
        self.credentialsProvider = credentialsProvider
        self.projectIdProvider = projectIdProvider
        self.transport = transport
        self.accessTokenProvider = accessTokenProvider
    }

    // MARK: - Authentication

    private func getAccessToken() async throws -> String {
        if let accessTokenProvider {
            return try await accessTokenProvider()
        }

        if let token = cachedAccessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }

        guard let credentialsJSON = credentialsProvider() else {
            throw GCPAPIError.missingCredentials
        }

        guard let credentialsData = credentialsJSON.data(using: .utf8) else {
            throw GCPAPIError.invalidCredentials
        }

        guard let serviceAccount = try? JSONDecoder().decode(GCPServiceAccount.self, from: credentialsData) else {
            throw GCPAPIError.invalidCredentials
        }

        let jwt = try createJWT(serviceAccount: serviceAccount)

        let tokenRequest = GCPTokenRequest(grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt)

        var request = URLRequest(url: oauthBase.appendingPathComponent("token"))
        request.httpMethod = "POST"

        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let formData = "grant_type=\(tokenRequest.grant_type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&assertion=\(tokenRequest.assertion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        request.httpBody = formData.data(using: .utf8)

        let (data, response) = try await transport.send(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GCPAPIError.http(-1)
        }

        guard httpResponse.statusCode == 200 else {
            throw GCPAPIError.http(httpResponse.statusCode)
        }

        do {
            let tokenResponse = try JSONDecoder().decode(GCPAuthTokenResponse.self, from: data)
            cachedAccessToken = tokenResponse.access_token
            tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in - 60))
            return tokenResponse.access_token
        } catch {
            throw GCPAPIError.decoding(error)
        }
    }

    private func createJWT(serviceAccount: GCPServiceAccount) throws -> String {
        let header = ["alg": "RS256", "typ": "JWT"]

        let now = Date()
        let exp = now.addingTimeInterval(3600)

        let payload: [String: Any] = [
            "iss": serviceAccount.client_email,
            "scope": Configuration.OAuth.googleCloudScope,
            "aud": serviceAccount.token_uri,
            "exp": Int(exp.timeIntervalSince1970),
            "iat": Int(now.timeIntervalSince1970),
        ]

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        let headerBase64 = base64URLEncode(headerData)
        let payloadBase64 = base64URLEncode(payloadData)

        let message = "\(headerBase64).\(payloadBase64)"
        guard let messageData = message.data(using: .utf8) else {
            throw GCPAPIError.jwt(NSError(
                domain: "GCPAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode JWT message"]
            ))
        }

        let signature = try signWithRSA(data: messageData, privateKeyPEM: serviceAccount.private_key)
        let signatureBase64 = base64URLEncode(signature)

        return "\(message).\(signatureBase64)"
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func signWithRSA(data: Data, privateKeyPEM: String) throws -> Data {
        let pemString = privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = pemString.components(separatedBy: .newlines)
        let base64Lines = lines.filter { line in
            !line.hasPrefix("-----") && !line.isEmpty
        }
        let base64Key = base64Lines.joined()

        guard let privateKeyData = Data(base64Encoded: base64Key) else {
            throw GCPAPIError.jwt(NSError(
                domain: "GCPAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode PEM private key base64"]
            ))
        }

        let pkcs1Key = try extractPKCS1FromPKCS8(privateKeyData)

        let keyAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]

        guard let privateKey = SecKeyCreateWithData(pkcs1Key as CFData, keyAttributes as CFDictionary, nil) else {
            throw GCPAPIError.jwt(NSError(
                domain: "GCPAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create SecKey from private key data"]
            ))
        }

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw GCPAPIError.jwt(NSError(
                domain: "GCPAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "RSA SHA256 signing not supported"]
            ))
        }

        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            nil
        ) else {
            throw GCPAPIError.jwt(NSError(
                domain: "GCPAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to sign JWT"]
            ))
        }

        return signature as Data
    }

    private func extractPKCS1FromPKCS8(_ pkcs8Data: Data) throws -> Data {
        let bytes = [UInt8](pkcs8Data)
        var index = 0
        let sequence = try derValue(tag: 0x30, bytes: bytes, index: &index)
        guard index == bytes.count else { throw invalidPrivateKey() }

        var fieldIndex = 0
        let version = try derValue(tag: 0x02, bytes: sequence, index: &fieldIndex)
        guard version == [0] else { throw invalidPrivateKey() }
        _ = try derValue(tag: 0x30, bytes: sequence, index: &fieldIndex)
        return try Data(derValue(tag: 0x04, bytes: sequence, index: &fieldIndex))
    }

    private func derValue(tag: UInt8, bytes: [UInt8], index: inout Int) throws -> [UInt8] {
        guard index < bytes.count, bytes[index] == tag else { throw invalidPrivateKey() }
        index += 1
        guard index < bytes.count else { throw invalidPrivateKey() }

        let firstLength = bytes[index]
        index += 1
        let length: Int
        if firstLength & 0x80 == 0 {
            length = Int(firstLength)
        } else {
            let count = Int(firstLength & 0x7F)
            guard count > 0, count < MemoryLayout<Int>.size, count <= bytes.count - index else {
                throw invalidPrivateKey()
            }
            var decoded = 0
            for _ in 0 ..< count {
                decoded = (decoded << 8) | Int(bytes[index])
                index += 1
            }
            length = decoded
        }

        guard length <= bytes.count - index else { throw invalidPrivateKey() }
        let value = Array(bytes[index ..< index + length])
        index += length
        return value
    }

    private func invalidPrivateKey() -> GCPAPIError {
        .jwt(NSError(
            domain: "GCPAPI",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid or truncated PKCS#8 private key"]
        ))
    }

    private func createAuthenticatedRequest(url: URL, method: String = "GET") async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let token = try await getAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return request
    }

    private func request<T: Codable>(url: URL, method: String = "GET", body: Data? = nil) async throws -> T {
        var request = try await createAuthenticatedRequest(url: url, method: method)
        request.httpBody = body

        let (data, response) = try await transport.send(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GCPAPIError.http(-1)
        }

        guard 200 ... 299 ~= httpResponse.statusCode else {
            if let gcpError = try? JSONDecoder().decode(GCPResponse.self, from: data).error {
                throw GCPAPIError.googleCloud(gcpError)
            }
            throw GCPAPIError.http(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GCPAPIError.decoding(error)
        }
    }

    // MARK: - Zones

    func listZones(nameFilter: String? = nil) async throws -> [GCPManagedZone] {
        guard let projectId = projectIdProvider() else {
            throw GCPAPIError.missingProjectId
        }

        var all: [GCPManagedZone] = []
        var nextPageToken: String?

        repeat {
            guard var comps = URLComponents(
                url: base.appendingPathComponent("dns/v1/projects/\(projectId)/managedZones"),
                resolvingAgainstBaseURL: false
            ) else {
                throw GCPAPIError.http(-1)
            }

            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "maxResults", value: "\(Constants.Pagination.googleCloudPageSize)"),
            ]

            if let token = nextPageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }

            comps.queryItems = queryItems
            guard let url = comps.url else {
                throw GCPAPIError.http(-1)
            }

            let response: GCPResponse = try await request(url: url, method: "GET")

            if let zones = response.managedZones {
                all += zones
            }

            nextPageToken = response.nextPageToken
        } while nextPageToken != nil

        if let filter = nameFilter, !filter.isEmpty {
            return all.filter { zone in
                let dnsName = zone.dnsName.hasSuffix(".") ? String(zone.dnsName.dropLast()) : zone.dnsName
                return dnsName.localizedCaseInsensitiveContains(filter) || zone.name
                    .localizedCaseInsensitiveContains(filter)
            }
        }

        return all
    }

    func createZone(name: String) async throws -> GCPManagedZone {
        guard let projectId = projectIdProvider() else {
            throw GCPAPIError.missingProjectId
        }

        let url = base.appendingPathComponent("dns/v1/projects/\(projectId)/managedZones")
        let request = GCPCreateManagedZoneRequest(
            name: managedZoneResourceName(for: name),
            dnsName: name.hasSuffix(".") ? name : "\(name).",
            description: "Created via DNSDeck",
            visibility: "public"
        )
        let body = try JSONEncoder().encode(request)
        return try await self.request(url: url, method: "POST", body: body)
    }

    func updateDomainNameservers(domain: String, nameservers: [String]) async throws {
        guard let projectId = projectIdProvider() else {
            throw GCPAPIError.missingProjectId
        }

        let registrationURL = domainsBase.appendingPathComponent(
            "v1/projects/\(projectId)/locations/global/registrations/\(domain)"
        )
        let registration: GCPDomainRegistration = try await request(url: registrationURL)
        let existingCustomDNS = registration.dnsSettings?.customDns
        let requestBody = GCPConfigureDNSSettingsRequest(
            dnsSettings: GCPDomainDNSSettings(
                customDns: GCPDomainCustomDNS(
                    nameServers: nameservers,
                    dsRecords: existingCustomDNS?.dsRecords
                )
            ),
            updateMask: existingCustomDNS == nil ? "customDns" : "customDns.nameServers",
            validateOnly: false
        )
        let configureURL = domainsBase.appendingPathComponent(
            "v1/projects/\(projectId)/locations/global/registrations/\(domain):configureDnsSettings"
        )
        let _: Empty = try await request(
            url: configureURL,
            method: "POST",
            body: JSONEncoder().encode(requestBody)
        )
    }

    private func managedZoneResourceName(for dnsName: String) -> String {
        var name = dnsName.lowercased()
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: #"[^a-z0-9-]"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if name.isEmpty {
            name = "dnsdeck-zone"
        } else if name.first?.isLetter != true {
            name = "z-\(name)"
        }
        return String(name.prefix(63))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: - Records

    func listRecords(zoneId: String) async throws -> [GCPResourceRecordSet] {
        guard let projectId = projectIdProvider() else {
            throw GCPAPIError.missingProjectId
        }

        var all: [GCPResourceRecordSet] = []
        var nextPageToken: String?

        repeat {
            guard var comps = URLComponents(
                url: base.appendingPathComponent("dns/v1/projects/\(projectId)/managedZones/\(zoneId)/rrsets"),
                resolvingAgainstBaseURL: false
            ) else {
                throw GCPAPIError.http(-1)
            }

            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "maxResults", value: "\(Constants.Pagination.googleCloudMaxPageSize)"),
            ]

            if let token = nextPageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }

            comps.queryItems = queryItems
            guard let url = comps.url else {
                throw GCPAPIError.http(-1)
            }

            let response: GCPResponse = try await request(
                url: url,
                method: "GET"
            )

            if let records = response.rrsets {
                all += records
            }

            nextPageToken = response.nextPageToken
        } while nextPageToken != nil

        return all
    }

    func createRecord(zoneId: String, record: GCPResourceRecordSet) async throws -> GCPResourceRecordSet {
        guard let projectId = projectIdProvider() else {
            throw GCPAPIError.missingProjectId
        }

        let url = base.appendingPathComponent("dns/v1/projects/\(projectId)/managedZones/\(zoneId)/changes")

        let change = GCPChange(additions: [record])
        let body = try JSONEncoder().encode(change)

        let _: Empty = try await request(url: url, method: "POST", body: body)

        return record
    }

    func updateRecord(
        zoneId: String,
        oldRecord: GCPResourceRecordSet,
        newRecord: GCPResourceRecordSet
    ) async throws -> GCPResourceRecordSet {
        guard let projectId = projectIdProvider() else {
            throw GCPAPIError.missingProjectId
        }

        let url = base.appendingPathComponent("dns/v1/projects/\(projectId)/managedZones/\(zoneId)/changes")

        let change = GCPChange(additions: [newRecord], deletions: [oldRecord])
        let body = try JSONEncoder().encode(change)

        let _: Empty = try await request(url: url, method: "POST", body: body)

        return newRecord
    }

    func deleteRecord(zoneId: String, record: GCPResourceRecordSet) async throws {
        guard let projectId = projectIdProvider() else {
            throw GCPAPIError.missingProjectId
        }

        let url = base.appendingPathComponent("dns/v1/projects/\(projectId)/managedZones/\(zoneId)/changes")

        let change = GCPChange(deletions: [record])
        let body = try JSONEncoder().encode(change)

        let _: Empty = try await request(url: url, method: "POST", body: body)
    }
}

private struct GCPTokenRequest: Codable {
    let grant_type: String
    let assertion: String
}

private struct Empty: Codable {}
