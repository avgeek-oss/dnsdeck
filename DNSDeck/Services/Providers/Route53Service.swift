import AvgeekNetworking
import CryptoKit
import Foundation

extension CharacterSet {
    static let awsQueryAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return allowed
    }()

    static let awsPathAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~/")
        return allowed
    }()
}

enum R53APIError: Error, LocalizedError {
    case missingCredentials
    case invalidCredentials
    case http(Int, String?)
    case aws(String)
    case decoding(Error)
    case encoding(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "AWS credentials are missing."
        case .invalidCredentials: "AWS credentials are invalid."
        case let .http(code, message): "HTTP error \(code): \(message ?? "Unknown error")"
        case let .aws(message): "AWS error: \(message)"
        case let .decoding(error): "Decoding error: \(error.localizedDescription)"
        case let .encoding(error): "Encoding error: \(error.localizedDescription)"
        case .invalidResponse: "Invalid response from AWS."
        }
    }
}

final class Route53Service {
    private let baseURL = Configuration.API.route53Base
    private let domainsBaseURL = "https://route53domains.us-east-1.amazonaws.com"
    private let region = "us-east-1"
    private let service = "route53"
    private let transport: any NetworkTransport
    private let dateProvider: () -> Date

    private let credentialsProvider: () -> (accessKeyId: String?, secretAccessKey: String?)

    init(
        credentialsProvider: @escaping () -> (accessKeyId: String?, secretAccessKey: String?),
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.credentialsProvider = credentialsProvider
        self.transport = transport
        self.dateProvider = dateProvider
    }

    // MARK: - Hosted Zones

    func listHostedZones() async throws -> [R53HostedZone] {
        var marker: String?
        return try await paginate {
            var query = [URLQueryItem(
                name: "maxitems",
                value: String(Constants.Pagination.route53PageSize)
            )]
            marker.map { query.append(URLQueryItem(name: "marker", value: $0)) }
            let root = try await xmlRoot(path: "hostedzone", queryItems: query)
            let zones = root.descendants(named: "HostedZone").map(parseHostedZone)
            marker = root.boolean(named: "IsTruncated") ? root.text(named: "NextMarker") : nil
            return (zones, marker != nil)
        }
    }

    func createHostedZone(name: String) async throws -> R53HostedZone {
        let root = try await xmlRoot(
            path: "hostedzone",
            method: "POST",
            body: xmlDocument(
                root: "CreateHostedZoneRequest",
                content: xml("Name", name) +
                    xml("CallerReference", UUID().uuidString) +
                    xmlContainer(
                        "HostedZoneConfig",
                        xml("Comment", "Created via DNSDeck") + xml("PrivateZone", "false")
                    )
            )
        )
        guard let element = root.descendant(named: "HostedZone") else {
            throw R53APIError.invalidResponse
        }
        var zone = parseHostedZone(element)
        zone.nameServers = root.descendants(named: "NameServer").compactMap(\.trimmedText)
        return zone
    }

    func updateDomainNameservers(domain: String, nameservers: [String]) async throws {
        guard let url = URL(string: domainsBaseURL) else {
            throw R53APIError.http(-1, "Invalid URL")
        }
        let body: Data
        do {
            body = try JSONEncoder().encode(
                R53UpdateDomainNameserversRequest(
                    domainName: domain,
                    nameservers: nameservers.map { R53DomainNameserver(name: $0) }
                )
            )
        } catch {
            throw R53APIError.encoding(error)
        }

        let credentials = credentialsProvider()
        guard let accessKeyId = credentials.accessKeyId?.trimmingCharacters(in: .whitespacesAndNewlines),
              let secretAccessKey = credentials.secretAccessKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessKeyId.isEmpty, !secretAccessKey.isEmpty
        else {
            throw R53APIError.missingCredentials
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Route53Domains_v20140515.UpdateDomainNameservers",
            forHTTPHeaderField: "X-Amz-Target"
        )
        signDomainRequest(
            &request,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            bodyData: body
        )

        let (data, response) = try await transport.send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw R53APIError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw R53APIError.http(httpResponse.statusCode, xmlMessage(from: data))
        }
    }

    // MARK: - Resource Record Sets

    func listResourceRecordSets(hostedZoneId: String) async throws -> [R53ResourceRecordSet] {
        var cursor: (name: String, type: String, identifier: String?)?
        return try await paginate {
            var queryItems = [URLQueryItem(
                name: "maxitems",
                value: String(Constants.Pagination.route53MaxPageSize)
            )]
            if let cursor {
                queryItems += [
                    URLQueryItem(name: "name", value: cursor.name),
                    URLQueryItem(name: "type", value: cursor.type),
                ]
                cursor.identifier.map {
                    queryItems.append(URLQueryItem(name: "identifier", value: $0))
                }
            }
            let root = try await xmlRoot(
                path: "hostedzone/\(cleanZoneId(hostedZoneId))/rrset",
                queryItems: queryItems
            )
            if root.boolean(named: "IsTruncated"),
               let name = root.text(named: "NextRecordName"),
               let type = root.text(named: "NextRecordType")
            {
                cursor = (name, type, root.text(named: "NextRecordIdentifier"))
            } else {
                cursor = nil
            }
            return (root.descendants(named: "ResourceRecordSet").map(parseRecordSet), cursor != nil)
        }
    }

    func createRecord(
        hostedZoneId: String,
        request recordRequest: CreateR53RecordRequest
    ) async throws {
        try await changeRecords(
            hostedZoneId: hostedZoneId,
            comment: "Created via DNSDeck",
            changes: [("CREATE", recordRequest.toResourceRecordSet())]
        )
    }

    func updateRecord(
        hostedZoneId: String,
        request recordRequest: UpdateR53RecordRequest
    ) async throws {
        try await changeRecords(
            hostedZoneId: hostedZoneId,
            comment: "Updated via DNSDeck",
            changes: [
                ("DELETE", recordRequest.oldRecord),
                ("CREATE", recordRequest.newRecord),
            ]
        )
    }

    func deleteRecord(hostedZoneId: String, record: R53ResourceRecordSet) async throws {
        try await changeRecords(
            hostedZoneId: hostedZoneId,
            comment: "Deleted via DNSDeck",
            changes: [("DELETE", record)]
        )
    }

    // MARK: - Internal

    private func cleanZoneId(_ zoneId: String) -> String {
        zoneId.replacingOccurrences(of: "/hostedzone/", with: "")
    }

    private func paginate<Item>(
        page: () async throws -> (items: [Item], hasNext: Bool)
    ) async throws -> [Item] {
        var result: [Item] = []
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= 1000 else { throw R53APIError.invalidResponse }
            let next = try await page()
            result += next.items
            if !next.hasNext { return result }
        } while true
    }

    private func xmlRoot(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> ProviderXMLNode {
        guard var components = URLComponents(string: "\(baseURL)/2013-04-01/\(path)") else {
            throw R53APIError.http(-1, "Invalid URL")
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw R53APIError.http(-1, "Invalid URL") }
        return try await xmlRoot(from: request(url: url, method: method, body: body))
    }

    private func request(url: URL, method: String, body: Data? = nil) async throws -> Data {
        let credentials = credentialsProvider()

        guard let accessKeyId = credentials.accessKeyId?.trimmingCharacters(in: .whitespacesAndNewlines),
              let secretAccessKey = credentials.secretAccessKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessKeyId.isEmpty, !secretAccessKey.isEmpty
        else {
            throw R53APIError.missingCredentials
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        }

        signRequest(&request, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, bodyData: body)

        let (data, response) = try await transport.send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw R53APIError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw R53APIError.http(httpResponse.statusCode, xmlMessage(from: data))
        }
        return data
    }

    private func signRequest(
        _ request: inout URLRequest,
        accessKeyId: String,
        secretAccessKey: String,
        bodyData: Data?
    ) {
        let date = dateProvider()
        let timestamp = awsTimestamp(date)
        let dateString = awsDate(date)
        request.setValue(timestamp, forHTTPHeaderField: "X-Amz-Date")

        let (canonicalRequest, signedHeaders) = createCanonicalRequest(request, bodyData: bodyData)
        let credentialScope = "\(dateString)/\(region)/\(service)/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(timestamp)\n\(credentialScope)\n\(sha256Hash(canonicalRequest))"
        let signature = calculateSignature(
            stringToSign: stringToSign,
            secretAccessKey: secretAccessKey,
            dateString: dateString,
            region: region,
            service: service
        )
        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
    }

    private func signDomainRequest(
        _ request: inout URLRequest,
        accessKeyId: String,
        secretAccessKey: String,
        bodyData: Data
    ) {
        let date = dateProvider()
        let timestamp = awsTimestamp(date)
        let dateString = awsDate(date)
        request.setValue(timestamp, forHTTPHeaderField: "X-Amz-Date")

        let host = request.url?.host ?? ""
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        let target = request.value(forHTTPHeaderField: "X-Amz-Target") ?? ""
        let canonicalHeaders = "content-type:\(contentType)\nhost:\(host)\nx-amz-date:\(timestamp)\nx-amz-target:\(target)\n"
        let signedHeaders = "content-type;host;x-amz-date;x-amz-target"
        let canonicalRequest = [
            request.httpMethod ?? "POST",
            "/",
            "",
            canonicalHeaders,
            signedHeaders,
            sha256Hash(bodyData),
        ].joined(separator: "\n")

        let domainService = "route53domains"
        let credentialScope = "\(dateString)/\(region)/\(domainService)/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(timestamp)\n\(credentialScope)\n\(sha256Hash(canonicalRequest))"
        let signature = calculateSignature(
            stringToSign: stringToSign,
            secretAccessKey: secretAccessKey,
            dateString: dateString,
            region: region,
            service: domainService
        )
        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
    }

    private func awsTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func awsDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func createCanonicalRequest(_ request: URLRequest, bodyData: Data?) -> (String, String) {
        let method = request.httpMethod ?? "GET"

        let rawPath = request.url?.path ?? "/"
        let path = rawPath.addingPercentEncoding(withAllowedCharacters: .awsPathAllowed) ?? rawPath

        let query: String
        if let queryString = request.url?.query, !queryString.isEmpty {
            let queryItems = queryString.components(separatedBy: "&")
                .compactMap { item -> String? in
                    let parts = item.components(separatedBy: "=")
                    guard parts.count == 2 else { return nil }
                    let key = parts[0].addingPercentEncoding(withAllowedCharacters: .awsQueryAllowed) ?? parts[0]
                    let value = parts[1].addingPercentEncoding(withAllowedCharacters: .awsQueryAllowed) ?? parts[1]
                    return "\(key)=\(value)"
                }
                .sorted()
            query = queryItems.joined(separator: "&")
        } else {
            query = ""
        }

        let host = request.url?.host ?? ""
        let amzDate = request.value(forHTTPHeaderField: "X-Amz-Date") ?? ""

        let headers = "host:\(host)\nx-amz-date:\(amzDate)"
        let signedHeaders = "host;x-amz-date"

        let payloadHash = bodyData.map { sha256Hash($0) } ?? sha256Hash(Data())

        let canonicalRequest = "\(method)\n\(path)\n\(query)\n\(headers)\n\n\(signedHeaders)\n\(payloadHash)"

        return (canonicalRequest, signedHeaders)
    }

    private func calculateSignature(
        stringToSign: String,
        secretAccessKey: String,
        dateString: String,
        region: String,
        service: String
    ) -> String {
        let kSecret = "AWS4\(secretAccessKey)".data(using: .utf8) ?? Data()
        let kDate = hmacSHA256(key: kSecret, data: dateString.data(using: .utf8) ?? Data())
        let kRegion = hmacSHA256(key: kDate, data: region.data(using: .utf8) ?? Data())
        let kService = hmacSHA256(key: kRegion, data: service.data(using: .utf8) ?? Data())
        let kSigning = hmacSHA256(key: kService, data: "aws4_request".data(using: .utf8) ?? Data())

        let signature = hmacSHA256(key: kSigning, data: stringToSign.data(using: .utf8) ?? Data())
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(authenticationCode)
    }

    private func sha256Hash(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256Hash(_ string: String) -> String {
        sha256Hash(string.data(using: .utf8) ?? Data())
    }

    private func changeRecords(
        hostedZoneId: String,
        comment: String,
        changes: [(action: String, record: R53ResourceRecordSet)]
    ) async throws {
        let changesXML = changes.map {
            xmlContainer("Change", xml("Action", $0.action) + recordSetXML($0.record))
        }.joined()
        _ = try await xmlRoot(
            path: "hostedzone/\(cleanZoneId(hostedZoneId))/rrset",
            method: "POST",
            body: xmlDocument(
                root: "ChangeResourceRecordSetsRequest",
                content: xmlContainer(
                    "ChangeBatch",
                    xml("Comment", comment) + xmlContainer("Changes", changesXML)
                )
            )
        )
    }

    private func parseHostedZone(_ element: ProviderXMLNode) -> R53HostedZone {
        let config = element.child(named: "Config") ?? element.child(named: "HostedZoneConfig")
        return R53HostedZone(
            id: element.text(named: "Id") ?? "",
            name: element.text(named: "Name") ?? "",
            callerReference: element.text(named: "CallerReference"),
            config: config.map {
                R53HostedZoneConfig(
                    privateZone: $0.optionalBoolean(named: "PrivateZone"),
                    comment: $0.text(named: "Comment")
                )
            },
            resourceRecordSetCount: element.text(named: "ResourceRecordSetCount").flatMap(Int.init)
        )
    }

    private func parseRecordSet(_ element: ProviderXMLNode) -> R53ResourceRecordSet {
        let alias = element.child(named: "AliasTarget")
        let geo = element.child(named: "GeoLocation")
        return R53ResourceRecordSet(
            name: element.text(named: "Name") ?? "",
            type: element.text(named: "Type") ?? "",
            ttl: element.text(named: "TTL").flatMap(Int.init),
            resourceRecords: element.child(named: "ResourceRecords")?
                .children(named: "ResourceRecord")
                .compactMap { $0.text(named: "Value").map(R53ResourceRecord.init) },
            aliasTarget: alias.flatMap {
                guard let name = $0.text(named: "DNSName"),
                      let zoneID = $0.text(named: "HostedZoneId")
                else { return nil }
                return R53AliasTarget(
                    dnsName: name,
                    hostedZoneId: zoneID,
                    evaluateTargetHealth: $0.boolean(named: "EvaluateTargetHealth")
                )
            },
            weight: element.text(named: "Weight").flatMap(Int.init),
            region: element.text(named: "Region"),
            geoLocation: geo.map {
                R53GeoLocation(
                    continentCode: $0.text(named: "ContinentCode"),
                    countryCode: $0.text(named: "CountryCode"),
                    subdivisionCode: $0.text(named: "SubdivisionCode")
                )
            },
            failover: element.text(named: "Failover"),
            multiValueAnswer: element.optionalBoolean(named: "MultiValueAnswer"),
            setIdentifier: element.text(named: "SetIdentifier"),
            healthCheckId: element.text(named: "HealthCheckId")
        )
    }

    private func recordSetXML(_ record: R53ResourceRecordSet) -> String {
        var content = xml("Name", record.name) + xml("Type", record.type)
        content += xml("SetIdentifier", record.setIdentifier)
        content += xml("Weight", record.weight)
        content += xml("Region", record.region)
        if let geo = record.geoLocation {
            content += xmlContainer(
                "GeoLocation",
                xml("ContinentCode", geo.continentCode) +
                    xml("CountryCode", geo.countryCode) +
                    xml("SubdivisionCode", geo.subdivisionCode)
            )
        }
        content += xml("Failover", record.failover)
        content += xml("MultiValueAnswer", record.multiValueAnswer)
        content += xml("TTL", record.ttl)
        if let records = record.resourceRecords {
            content += xmlContainer(
                "ResourceRecords",
                records.map { xmlContainer("ResourceRecord", xml("Value", $0.value)) }.joined()
            )
        }
        if let alias = record.aliasTarget {
            content += xmlContainer(
                "AliasTarget",
                xml("HostedZoneId", alias.hostedZoneId) +
                    xml("DNSName", alias.dnsName) +
                    xml("EvaluateTargetHealth", alias.evaluateTargetHealth)
            )
        }
        content += xml("HealthCheckId", record.healthCheckId)
        return xmlContainer("ResourceRecordSet", content)
    }

    private func xmlRoot(from data: Data) throws -> ProviderXMLNode {
        do {
            return try ProviderXMLNode.parse(data)
        } catch {
            throw R53APIError.decoding(error)
        }
    }

    private func xmlDocument(root: String, content: String) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <\(root) xmlns="\(Configuration.Route53.xmlNamespace)">\(content)</\(root)>
            """.utf8
        )
    }

    private func xml(_ name: String, _ value: String?) -> String {
        value.map { "<\(name)>\($0.xmlEscaped)</\(name)>" } ?? ""
    }

    private func xml(_ name: String, _ value: Int?) -> String {
        xml(name, value.map(String.init))
    }

    private func xml(_ name: String, _ value: Bool?) -> String {
        xml(name, value.map { $0 ? "true" : "false" })
    }

    private func xmlContainer(_ name: String, _ content: String) -> String {
        "<\(name)>\(content)</\(name)>"
    }

    private func xmlMessage(from data: Data) -> String? {
        try? xmlRoot(from: data).text(named: "Message")
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
