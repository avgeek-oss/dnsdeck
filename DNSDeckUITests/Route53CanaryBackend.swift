import CryptoKit
import Foundation

struct Route53CanaryBackend: ProviderCanaryBackend {
    private let configuration: ProviderCanaryConfiguration
    private let accessKeyID: String
    private let secretAccessKey: String
    private let baseURL = URL(string: "https://route53.amazonaws.com/2013-04-01")!

    init(configuration: ProviderCanaryConfiguration) throws {
        self.configuration = configuration
        accessKeyID = try configuration.credential("accessKeyId")
        secretAccessKey = try configuration.credential("secretAccessKey")
    }

    func deleteStaleRecords(olderThan cutoff: Date) async throws -> Int {
        let zoneID = try await zoneID()
        let staleRecords = try await records(zoneID: zoneID).filter { record in
            guard !isRunRecord(record.normalizedName),
                  ProviderCanaryOwnerMatcher.isTestRecord(
                      record.normalizedName,
                      zoneName: configuration.zoneName
                  ),
                  let createdAt = ProviderCanaryOwnerMatcher.creationDate(
                      record.normalizedName,
                      zoneName: configuration.zoneName
                  )
            else {
                return false
            }
            return createdAt < cutoff
        }
        if !staleRecords.isEmpty {
            try await delete(records: staleRecords, zoneID: zoneID)
            try await assertRecordsAbsent(
                zoneID: zoneID,
                keys: Set(staleRecords.map(\.cleanupKey))
            )
        }
        return staleRecords.count
    }

    func deleteRunRecordsIfPresent() async throws -> Int {
        let zoneID = try await zoneID()
        let records = try await matchingRunRecords(zoneID: zoneID)
        if !records.isEmpty {
            try await delete(records: records, zoneID: zoneID)
        }
        try await assertRunRecordsAbsent(zoneID: zoneID)
        return records.count
    }

    func prepareRunRecords() async throws {
        guard let fixture = configuration.multiValueMXRecord else { return }
        let zoneID = try await zoneID()
        let record = Route53CanaryRecord(
            name: "\(fixture.fullyQualifiedName).",
            type: "MX",
            ttl: configuration.definition.importTTL,
            values: fixture.initialValues.map {
                "\($0.priority ?? 10) \($0.content)"
            }
        )
        try await change(
            records: [record],
            action: "CREATE",
            comment: "DNSDeck provider canary setup",
            zoneID: zoneID
        )
    }

    func runRecords() async throws -> [ProviderCanaryLiveRecord] {
        let zoneID = try await zoneID()
        return try await matchingRunRecords(zoneID: zoneID).map(\.liveRecord)
    }

    private func zoneID() async throws -> String {
        var zones: [Route53CanaryZone] = []
        var marker: String?

        repeat {
            var queryItems = [URLQueryItem(name: "maxitems", value: "100")]
            if let marker {
                queryItems.append(URLQueryItem(name: "marker", value: marker))
            }
            let root = try await xmlRequest(path: ["hostedzone"], queryItems: queryItems)
            zones += root.descendants(named: "HostedZone").map {
                Route53CanaryZone(
                    id: $0.text(named: "Id") ?? "",
                    name: Self.normalizedDNSName($0.text(named: "Name") ?? "")
                )
            }
            marker = root.boolean(named: "IsTruncated")
                ? root.text(named: "NextMarker")
                : nil
        } while marker != nil

        guard let zone = zones.first(where: { $0.name == configuration.zoneName }) else {
            throw ProviderCanaryBackendError.zoneNotFound(
                provider: configuration.definition.displayName,
                zone: configuration.zoneName
            )
        }
        return zone.id.replacingOccurrences(of: "/hostedzone/", with: "")
    }

    private func matchingRunRecords(zoneID: String) async throws -> [Route53CanaryRecord] {
        try await records(zoneID: zoneID).filter { isRunRecord($0.normalizedName) }
    }

    private func isRunRecord(_ name: String) -> Bool {
        ProviderCanaryOwnerMatcher.isRunRecord(
            name,
            zoneName: configuration.zoneName,
            runPrefix: configuration.runPrefix
        )
    }

    private func records(zoneID: String) async throws -> [Route53CanaryRecord] {
        var records: [Route53CanaryRecord] = []
        var cursor: (name: String, type: String, identifier: String?)?

        repeat {
            var queryItems = [URLQueryItem(name: "maxitems", value: "300")]
            if let cursor {
                queryItems += [
                    URLQueryItem(name: "name", value: cursor.name),
                    URLQueryItem(name: "type", value: cursor.type),
                ]
                if let identifier = cursor.identifier {
                    queryItems.append(URLQueryItem(name: "identifier", value: identifier))
                }
            }

            let root = try await xmlRequest(
                path: ["hostedzone", zoneID, "rrset"],
                queryItems: queryItems
            )
            records += root.descendants(named: "ResourceRecordSet").map(Self.record)
            if root.boolean(named: "IsTruncated"),
               let name = root.text(named: "NextRecordName"),
               let type = root.text(named: "NextRecordType")
            {
                cursor = (name, type, root.text(named: "NextRecordIdentifier"))
            } else {
                cursor = nil
            }
        } while cursor != nil

        return records
    }

    private func delete(records: [Route53CanaryRecord], zoneID: String) async throws {
        try await change(
            records: records.sorted(by: Self.deletionOrder),
            action: "DELETE",
            comment: "DNSDeck provider canary cleanup",
            zoneID: zoneID
        )
    }

    private func change(
        records: [Route53CanaryRecord],
        action: String,
        comment: String,
        zoneID: String
    ) async throws {
        let changes = records
            .map { record in
                Self.xmlContainer(
                    "Change",
                    Self.xml("Action", action) + Self.recordXML(record)
                )
            }
            .joined()
        let body = Self.xmlDocument(
            root: "ChangeResourceRecordSetsRequest",
            content: Self.xmlContainer(
                "ChangeBatch",
                Self.xml("Comment", comment) +
                    Self.xmlContainer("Changes", changes)
            )
        )
        _ = try await xmlRequest(
            path: ["hostedzone", zoneID, "rrset"],
            method: "POST",
            body: body
        )
    }

    private func assertRecordsAbsent(
        zoneID: String,
        keys: Set<Route53CanaryRecordKey>
    ) async throws {
        for attempt in 0 ..< 30 {
            let remainingRecords = try await records(zoneID: zoneID)
            let remainingKeys = Set(remainingRecords.map(\.cleanupKey))
            if keys.isDisjoint(with: remainingKeys) {
                return
            }
            guard attempt < 29 else {
                throw ProviderCanaryBackendError.recordsStillPresent
            }
            try await Task.sleep(for: .seconds(2))
        }
    }

    private func assertRunRecordsAbsent(zoneID: String) async throws {
        for attempt in 0 ..< 30 {
            if try await matchingRunRecords(zoneID: zoneID).isEmpty {
                return
            }
            guard attempt < 29 else {
                throw ProviderCanaryBackendError.recordsStillPresent
            }
            try await Task.sleep(for: .seconds(2))
        }
    }

    private func xmlRequest(
        path: [String],
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> ProviderCanaryXMLNode {
        let data = try await request(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body
        )
        return try ProviderCanaryXMLNode.parse(data)
    }

    private func request(
        path: [String],
        method: String,
        queryItems: [URLQueryItem],
        body: Data?
    ) async throws -> Data {
        let url = path.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ProviderCanaryBackendError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let requestURL = components.url else {
            throw ProviderCanaryBackendError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        }
        sign(&request, body: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ProviderCanaryBackendError.invalidResponse
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw ProviderCanaryBackendError.requestFailed(
                provider: configuration.definition.displayName,
                statusCode: response.statusCode
            )
        }
        return data
    }

    private func sign(_ request: inout URLRequest, body: Data?) {
        let date = Date()
        let timestamp = Self.timestamp(date)
        let dateString = Self.date(date)
        request.setValue(timestamp, forHTTPHeaderField: "X-Amz-Date")

        let canonicalRequest = Self.canonicalRequest(request, body: body)
        let scope = "\(dateString)/us-east-1/route53/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            timestamp,
            scope,
            Self.sha256(canonicalRequest),
        ].joined(separator: "\n")
        let signature = Self.signature(
            stringToSign: stringToSign,
            secretAccessKey: secretAccessKey,
            date: dateString
        )
        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), " +
                "SignedHeaders=host;x-amz-date, Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
    }

    private static func canonicalRequest(_ request: URLRequest, body: Data?) -> String {
        let url = request.url!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath.isEmpty == false
            ? components!.percentEncodedPath
            : "/"
        let query = components?
            .queryItems?
            .map {
                "\(awsEncode($0.name))=\(awsEncode($0.value ?? ""))"
            }
            .sorted()
            .joined(separator: "&") ?? ""
        let host = url.host ?? ""
        let timestamp = request.value(forHTTPHeaderField: "X-Amz-Date") ?? ""
        return [
            request.httpMethod ?? "GET",
            path,
            query,
            "host:\(host)\nx-amz-date:\(timestamp)\n",
            "host;x-amz-date",
            sha256(body ?? Data()),
        ].joined(separator: "\n")
    }

    private static func signature(
        stringToSign: String,
        secretAccessKey: String,
        date: String
    ) -> String {
        let dateKey = hmac(key: Data("AWS4\(secretAccessKey)".utf8), value: date)
        let regionKey = hmac(key: dateKey, value: "us-east-1")
        let serviceKey = hmac(key: regionKey, value: "route53")
        let signingKey = hmac(key: serviceKey, value: "aws4_request")
        return hmac(key: signingKey, value: stringToSign)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func hmac(key: Data, value: String) -> Data {
        Data(
            HMAC<SHA256>.authenticationCode(
                for: Data(value.utf8),
                using: SymmetricKey(data: key)
            )
        )
    }

    private static func sha256(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    private static func sha256(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }

    private static func timestamp(_ date: Date) -> String {
        formatted(date, format: "yyyyMMdd'T'HHmmss'Z'")
    }

    private static func date(_ date: Date) -> String {
        formatted(date, format: "yyyyMMdd")
    }

    private static func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func awsEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func record(_ node: ProviderCanaryXMLNode) -> Route53CanaryRecord {
        Route53CanaryRecord(
            name: node.text(named: "Name") ?? "",
            type: node.text(named: "Type") ?? "",
            ttl: node.text(named: "TTL").flatMap(Int.init),
            values: node.child(named: "ResourceRecords")?
                .children(named: "ResourceRecord")
                .compactMap { $0.text(named: "Value") } ?? []
        )
    }

    private static func recordXML(_ record: Route53CanaryRecord) -> String {
        xmlContainer(
            "ResourceRecordSet",
            xml("Name", record.name) +
                xml("Type", record.type) +
                xml("TTL", record.ttl.map(String.init)) +
                xmlContainer(
                    "ResourceRecords",
                    record.values.map {
                        xmlContainer("ResourceRecord", xml("Value", $0))
                    }.joined()
                )
        )
    }

    private static func deletionOrder(
        _ lhs: Route53CanaryRecord,
        _ rhs: Route53CanaryRecord
    ) -> Bool {
        deletionRank(lhs.type) < deletionRank(rhs.type)
    }

    private static func deletionRank(_ type: String) -> Int {
        switch type {
        case "DS": 0
        case "NS": 2
        default: 1
        }
    }

    private static func normalizedDNSName(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    }

    private static func xmlDocument(root: String, content: String) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <\(root) xmlns="https://route53.amazonaws.com/doc/2013-04-01/">\(content)</\(root)>
            """.utf8
        )
    }

    private static func xml(_ name: String, _ value: String?) -> String {
        value.map { "<\(name)>\($0.xmlEscaped)</\(name)>" } ?? ""
    }

    private static func xmlContainer(_ name: String, _ content: String) -> String {
        "<\(name)>\(content)</\(name)>"
    }
}

private struct Route53CanaryZone {
    let id: String
    let name: String
}

private struct Route53CanaryRecord {
    let name: String
    let type: String
    let ttl: Int?
    let values: [String]

    var normalizedName: String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    }

    var cleanupKey: Route53CanaryRecordKey {
        Route53CanaryRecordKey(name: normalizedName, type: type)
    }

    var liveRecord: ProviderCanaryLiveRecord {
        let liveValues = values.map { value in
            ProviderCanaryLiveValue(
                content: type == "MX" ? Self.removingPriority(value) : value,
                priority: type == "MX" ? Self.priority(value) : nil
            )
        }
        let primaryValue = liveValues.first ?? ProviderCanaryLiveValue(content: "", priority: nil)
        return ProviderCanaryLiveRecord(
            name: normalizedName,
            type: type,
            content: primaryValue.content,
            priority: primaryValue.priority,
            comment: nil,
            ttl: ttl,
            values: liveValues
        )
    }

    private static func priority(_ value: String) -> Int? {
        value.split(whereSeparator: \Character.isWhitespace).first.flatMap { Int($0) }
    }

    private static func removingPriority(_ value: String) -> String {
        let parts = value.split(whereSeparator: \Character.isWhitespace)
        guard parts.first.flatMap({ Int($0) }) != nil else { return value }
        return parts.dropFirst().joined(separator: " ")
    }
}

private struct Route53CanaryRecordKey: Hashable {
    let name: String
    let type: String
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
