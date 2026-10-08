import AvgeekNetworking
import Foundation

final class OracleCloudDNSService {
    typealias Credentials = (
        tenancyId: String?,
        userId: String?,
        fingerprint: String?,
        privateKeyPEM: String?,
        region: String?,
        compartmentId: String?,
        realmDomain: String?
    )

    private struct Context {
        let credentials: ValidatedCredentials
        let client: ProviderHTTPClient
        let signer: OCIRequestSigner
    }

    private struct ValidatedCredentials {
        let tenancyId: String
        let userId: String
        let fingerprint: String
        let privateKeyPEM: String
        let region: String
        let compartmentId: String
        let realmDomain: String
    }

    private static let maximumPages = 1000
    private static let maximumZonePolls = 60
    private static let pageSize = 1000

    private let credentialsProvider: () -> Credentials
    private let endpointOverride: URL?
    private let transport: any NetworkTransport
    private let sleep: ProviderHTTPClient.Sleep
    private let now: () -> Date
    private let signatureProvider: OCIRequestSigner.SignatureProvider?

    init(
        credentialsProvider: @escaping () -> Credentials,
        endpointURL: URL? = nil,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep,
        now: @escaping () -> Date = Date.init,
        signatureProvider: OCIRequestSigner.SignatureProvider? = nil
    ) {
        self.credentialsProvider = credentialsProvider
        endpointOverride = endpointURL
        self.transport = transport
        self.sleep = sleep
        self.now = now
        self.signatureProvider = signatureProvider
    }

    func listZones() async throws -> [OracleCloudZone] {
        let context = try makeContext()
        var zones: [OracleCloudZone] = []
        var page: String?
        var seenPages: Set<String> = []

        for _ in 0 ..< Self.maximumPages {
            let response = try await send(
                context: context,
                method: "GET",
                url: zonesURL(context: context, page: page),
                retryPolicy: .transientRead()
            )
            try zones.append(contentsOf: context.client.decode([OracleCloudZone].self, from: response))
            guard let nextPage = response.response.value(forHTTPHeaderField: "opc-next-page"),
                  !nextPage.isEmpty
            else {
                return zones
            }
            try recordPage(nextPage, seen: &seenPages, operation: "zone listing")
            page = nextPage
        }

        throw paginationLimit(operation: "zone listing")
    }

    func getZone(_ zone: OracleCloudZone) async throws -> OracleCloudZone {
        try await getZone(id: zone.id)
    }

    func createZone(name: String) async throws -> OracleCloudZone {
        let context = try makeContext()
        let request = OracleCloudCreateZoneRequest(
            name: name.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            compartmentId: context.credentials.compartmentId,
            zoneType: "PRIMARY",
            scope: "GLOBAL",
            migrationSource: "NONE"
        )
        let body = try JSONEncoder().encode(request)
        let retryToken = UUID().uuidString.lowercased()
        let response = try await send(
            context: context,
            method: "POST",
            url: context.client.url(
                pathComponents: ["zones"],
                queryItems: [URLQueryItem(name: "scope", value: "GLOBAL")]
            ),
            headers: ["opc-retry-token": retryToken],
            body: body,
            retryPolicy: .idempotentWrite()
        )
        var zone = try context.client.decode(OracleCloudZone.self, from: response)
        zone.etag = response.response.value(forHTTPHeaderField: "etag")
        if zone.lifecycleState.caseInsensitiveCompare("ACTIVE") == .orderedSame {
            return zone
        }

        for _ in 0 ..< Self.maximumZonePolls {
            if zone.lifecycleState.caseInsensitiveCompare("FAILED") == .orderedSame {
                throw ProviderAPIError.operationFailed(
                    provider: .oracleCloud,
                    operation: "zone creation",
                    message: "the zone entered the FAILED lifecycle state"
                )
            }
            try await sleep(1)
            zone = try await getZone(id: zone.id)
            if zone.lifecycleState.caseInsensitiveCompare("ACTIVE") == .orderedSame {
                return zone
            }
        }

        throw ProviderAPIError.operationTimedOut(provider: .oracleCloud, operation: "zone creation")
    }

    func deleteZone(_ zone: OracleCloudZone, etag: String) async throws {
        let context = try makeContext()
        _ = try await send(
            context: context,
            method: "DELETE",
            url: zoneURL(context: context, id: zone.id),
            headers: ["If-Match": etag],
            retryPolicy: .transientResponseWrite()
        )
    }

    func listRecordSets(zone: OracleCloudZone) async throws -> [OracleCloudRRSet] {
        let context = try makeContext()
        var records: [OracleCloudRecord] = []
        var page: String?
        var seenPages: Set<String> = []

        for _ in 0 ..< Self.maximumPages {
            let response = try await send(
                context: context,
                method: "GET",
                url: recordsURL(context: context, zoneId: zone.id, page: page),
                retryPolicy: .transientRead()
            )
            let collection = try context.client.decode(OracleCloudRecordCollection.self, from: response)
            records.append(contentsOf: collection.items)
            guard let nextPage = response.response.value(forHTTPHeaderField: "opc-next-page"),
                  !nextPage.isEmpty
            else {
                return OracleCloudRRSet.grouped(records)
            }
            try recordPage(nextPage, seen: &seenPages, operation: "record listing")
            page = nextPage
        }

        throw paginationLimit(operation: "record listing")
    }

    func rrSetIfExists(zone: OracleCloudZone, domain: String, type: String) async throws -> OracleCloudRRSet? {
        do {
            return try await getRRSet(zone: zone, domain: domain, type: type)
        } catch let ProviderAPIError.http(_, statusCode, _, _, _) where statusCode == 404 {
            return nil
        }
    }

    func getRRSet(zone: OracleCloudZone, domain: String, type: String) async throws -> OracleCloudRRSet {
        let context = try makeContext()
        var records: [OracleCloudRecord] = []
        var etag: String?
        var page: String?
        var seenPages: Set<String> = []

        for _ in 0 ..< Self.maximumPages {
            let response = try await send(
                context: context,
                method: "GET",
                url: rrSetURL(
                    context: context,
                    zoneId: zone.id,
                    domain: domain,
                    type: type,
                    page: page,
                    paginated: true
                ),
                retryPolicy: .transientRead()
            )
            let collection = try context.client.decode(OracleCloudRecordCollection.self, from: response)
            records.append(contentsOf: collection.items)
            etag = etag ?? response.response.value(forHTTPHeaderField: "etag")
            guard let nextPage = response.response.value(forHTTPHeaderField: "opc-next-page"),
                  !nextPage.isEmpty
            else {
                return OracleCloudRRSet(
                    domain: records.first?.domain ?? domain,
                    type: records.first?.rtype.uppercased() ?? type.uppercased(),
                    items: records,
                    etag: etag
                )
            }
            try recordPage(nextPage, seen: &seenPages, operation: "RRset retrieval")
            page = nextPage
        }

        throw paginationLimit(operation: "RRset retrieval")
    }

    func putRRSet(
        zone: OracleCloudZone,
        mutation: OracleCloudRRSetMutation,
        ifMatch: String? = nil
    ) async throws -> OracleCloudRRSet {
        let context = try makeContext()
        let body = try JSONEncoder().encode(mutation.request)
        let response = try await send(
            context: context,
            method: "PUT",
            url: rrSetURL(
                context: context,
                zoneId: zone.id,
                domain: mutation.domain,
                type: mutation.type,
                page: nil,
                paginated: false
            ),
            headers: ifMatch.map { ["If-Match": $0] } ?? [:],
            body: body,
            retryPolicy: .transientResponseWrite()
        )
        let collection = try context.client.decode(OracleCloudRecordCollection.self, from: response)
        let records = collection.items.isEmpty ? mutation.request.items.map {
            OracleCloudRecord(
                domain: $0.domain,
                recordHash: nil,
                isProtected: false,
                rdata: $0.rdata,
                rrsetVersion: nil,
                rtype: $0.rtype,
                ttl: $0.ttl
            )
        } : collection.items
        return OracleCloudRRSet(
            domain: records.first?.domain ?? mutation.domain,
            type: records.first?.rtype.uppercased() ?? mutation.type,
            items: records,
            etag: response.response.value(forHTTPHeaderField: "etag")
        )
    }

    func deleteRRSet(
        zone: OracleCloudZone,
        domain: String,
        type: String,
        etag: String
    ) async throws {
        let context = try makeContext()
        _ = try await send(
            context: context,
            method: "DELETE",
            url: rrSetURL(
                context: context,
                zoneId: zone.id,
                domain: domain,
                type: type,
                page: nil,
                paginated: false
            ),
            headers: ["If-Match": etag],
            retryPolicy: .transientResponseWrite()
        )
    }

    static func endpoint(region: String, realmDomain: String = "oraclecloud.com") throws -> URL {
        guard validRegion(region), validRealmDomain(realmDomain),
              let url = URL(string: "https://dns.\(region).oci.\(realmDomain)")
        else {
            throw ProviderAPIError.invalidURL(provider: .oracleCloud)
        }
        return url
    }

    private func getZone(id: String) async throws -> OracleCloudZone {
        let context = try makeContext()
        let response = try await send(
            context: context,
            method: "GET",
            url: zoneURL(context: context, id: id),
            retryPolicy: .transientRead()
        )
        var zone = try context.client.decode(OracleCloudZone.self, from: response)
        zone.etag = response.response.value(forHTTPHeaderField: "etag")
        return zone
    }

    private func send(
        context: Context,
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy
    ) async throws -> ProviderHTTPResponse {
        var signedHeaders = try context.signer.headers(method: method, url: url, body: body, date: now())
        for (name, value) in headers {
            signedHeaders[name] = value
        }
        signedHeaders["opc-client-request-id"] = UUID().uuidString.lowercased()
        return try await context.client.send(
            method: method,
            url: url,
            headers: signedHeaders,
            body: body,
            retryPolicy: retryPolicy
        )
    }

    private func makeContext() throws -> Context {
        let credentials = try validatedCredentials()
        let endpoint: URL = if let endpointOverride {
            endpointOverride
        } else {
            try Self.endpoint(region: credentials.region, realmDomain: credentials.realmDomain)
        }
        guard endpoint.scheme?.lowercased() == "https", endpoint.user == nil, endpoint.password == nil else {
            throw ProviderAPIError.invalidURL(provider: .oracleCloud)
        }
        let baseURL = endpoint.appendingPathComponent("20180115")
        return Context(
            credentials: credentials,
            client: ProviderHTTPClient(
                provider: .oracleCloud,
                baseURL: baseURL,
                transport: transport,
                sleep: sleep,
                now: now
            ),
            signer: OCIRequestSigner(
                tenancyId: credentials.tenancyId,
                userId: credentials.userId,
                fingerprint: credentials.fingerprint,
                privateKeyPEM: credentials.privateKeyPEM,
                signatureProvider: signatureProvider
            )
        )
    }

    private func validatedCredentials() throws -> ValidatedCredentials {
        let values = credentialsProvider()
        let tenancyId = try headerCredential(values.tenancyId, field: "Tenancy OCID")
        let userId = try headerCredential(values.userId, field: "User OCID")
        let fingerprint = try headerCredential(values.fingerprint, field: "Key Fingerprint")
        let privateKeyPEM = try requiredCredential(values.privateKeyPEM, field: "Private API Key")
        let region = try requiredCredential(values.region, field: "Region").lowercased()
        let compartmentId = try requiredCredential(values.compartmentId, field: "Compartment OCID")
        let realmDomain = values.realmDomain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedRealm = realmDomain.flatMap { $0.isEmpty ? nil : $0 } ?? "oraclecloud.com"
        guard Self.validRegion(region), Self.validRealmDomain(resolvedRealm) else {
            throw ProviderAPIError.invalidURL(provider: .oracleCloud)
        }
        return ValidatedCredentials(
            tenancyId: tenancyId,
            userId: userId,
            fingerprint: fingerprint,
            privateKeyPEM: privateKeyPEM,
            region: region,
            compartmentId: compartmentId,
            realmDomain: resolvedRealm
        )
    }

    private func requiredCredential(_ value: String?, field: String) throws -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .oracleCloud, field: field)
        }
        return value
    }

    private func headerCredential(_ value: String?, field: String) throws -> String {
        let value = try requiredCredential(value, field: field)
        guard value.rangeOfCharacter(from: CharacterSet(charactersIn: "\"\r\n/")) == nil else {
            throw ProviderAPIError.operationFailed(
                provider: .oracleCloud,
                operation: "credential validation",
                message: "\(field) contains a character that is not valid in an OCI signature key ID"
            )
        }
        return value
    }

    private func zonesURL(context: Context, page: String?) throws -> URL {
        var queryItems = [
            URLQueryItem(name: "compartmentId", value: context.credentials.compartmentId),
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "scope", value: "GLOBAL"),
        ]
        if let page { queryItems.append(URLQueryItem(name: "page", value: page)) }
        return try context.client.url(pathComponents: ["zones"], queryItems: queryItems)
    }

    private func zoneURL(context: Context, id: String) throws -> URL {
        try context.client.url(
            pathComponents: ["zones", id],
            queryItems: [URLQueryItem(name: "scope", value: "GLOBAL")]
        )
    }

    private func recordsURL(context: Context, zoneId: String, page: String?) throws -> URL {
        var queryItems = [
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "scope", value: "GLOBAL"),
        ]
        if let page { queryItems.append(URLQueryItem(name: "page", value: page)) }
        return try context.client.url(
            pathComponents: ["zones", zoneId, "records"],
            queryItems: queryItems
        )
    }

    private func rrSetURL(
        context: Context,
        zoneId: String,
        domain: String,
        type: String,
        page: String?,
        paginated: Bool
    ) throws -> URL {
        var queryItems = [URLQueryItem(name: "scope", value: "GLOBAL")]
        if paginated { queryItems.insert(URLQueryItem(name: "limit", value: String(Self.pageSize)), at: 0) }
        if let page { queryItems.append(URLQueryItem(name: "page", value: page)) }
        return try context.client.url(
            pathComponents: ["zones", zoneId, "records", domain, type.uppercased()],
            queryItems: queryItems
        )
    }

    private func recordPage(_ page: String, seen: inout Set<String>, operation: String) throws {
        guard seen.insert(page).inserted else {
            throw ProviderAPIError.operationFailed(
                provider: .oracleCloud,
                operation: operation,
                message: "the API returned a pagination cycle"
            )
        }
    }

    private func paginationLimit(operation: String) -> ProviderAPIError {
        ProviderAPIError.operationFailed(
            provider: .oracleCloud,
            operation: operation,
            message: "pagination exceeded \(Self.maximumPages) pages"
        )
    }

    private static func validRegion(_ value: String) -> Bool {
        guard let first = value.first, let last = value.last, first.isASCII, last.isASCII,
              first.isLetter || first.isNumber, last.isLetter || last.isNumber
        else {
            return false
        }
        return value.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }

    private static func validRealmDomain(_ value: String) -> Bool {
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            guard let first = label.first, let last = label.last,
                  first.isLetter || first.isNumber, last.isLetter || last.isNumber
            else {
                return false
            }
            return label.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
        }
    }
}
