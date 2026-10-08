import Foundation

struct CloudflareCanaryBackend: ProviderCanaryBackend {
    private let configuration: ProviderCanaryConfiguration
    private let accountID: String
    private let token: String
    private let baseURL = URL(string: "https://api.cloudflare.com/client/v4")!

    init(configuration: ProviderCanaryConfiguration) throws {
        self.configuration = configuration
        accountID = try configuration.credential("accountId")
        token = try configuration.credential("token")
    }

    func deleteStaleRecords(olderThan cutoff: Date) async throws -> Int {
        let zoneID = try await zoneID()
        let records = try await records(zoneID: zoneID)
        let staleRecords = records.filter { record in
            guard !isRunRecord(record.name),
                  ProviderCanaryOwnerMatcher.isTestRecord(
                      record.name,
                      zoneName: configuration.zoneName
                  ),
                  let createdOn = record.createdOn,
                  let creationDate = Self.timestamp(createdOn)
            else {
                return false
            }
            return creationDate < cutoff
        }
        for record in staleRecords.sorted(by: Self.deletionOrder) {
            try await delete(record: record, zoneID: zoneID)
        }
        return staleRecords.count
    }

    func deleteRunRecordsIfPresent() async throws -> Int {
        let zoneID = try await zoneID()
        let records = try await matchingRunRecords(zoneID: zoneID)
        for record in records.sorted(by: Self.deletionOrder) {
            try await delete(record: record, zoneID: zoneID)
        }
        try await ProviderCanaryCleanup.assertRunRecordsAbsent {
            try await matchingRunRecords(zoneID: zoneID).map(\.liveRecord)
        }
        return records.count
    }

    func runRecords() async throws -> [ProviderCanaryLiveRecord] {
        let zoneID = try await zoneID()
        return try await matchingRunRecords(zoneID: zoneID).map(\.liveRecord)
    }

    private func zoneID() async throws -> String {
        let zones: [CloudflareCanaryZone] = try await request(
            path: ["zones"],
            queryItems: [
                URLQueryItem(name: "account.id", value: accountID),
                URLQueryItem(name: "name", value: configuration.zoneName),
                URLQueryItem(name: "match", value: "all"),
            ]
        )
        guard let zone = zones.first(where: { $0.name == configuration.zoneName }) else {
            throw ProviderCanaryBackendError.zoneNotFound(
                provider: configuration.definition.displayName,
                zone: configuration.zoneName
            )
        }
        return zone.id
    }

    private func matchingRunRecords(zoneID: String) async throws -> [CloudflareCanaryRecord] {
        try await records(zoneID: zoneID).filter { isRunRecord($0.name) }
    }

    private func records(zoneID: String) async throws -> [CloudflareCanaryRecord] {
        // Keep this below the comprehensive fixture count so the live canary exercises pagination.
        let pageSize = 10
        var page = 1
        var records: [CloudflareCanaryRecord] = []

        while true {
            let envelope: CloudflareCanaryEnvelope<[CloudflareCanaryRecord]> = try await requestEnvelope(
                path: ["zones", zoneID, "dns_records"],
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "per_page", value: String(pageSize)),
                ]
            )
            guard envelope.success, let pageRecords = envelope.result else {
                throw ProviderCanaryBackendError.invalidResponse
            }
            records += pageRecords

            guard let resultInfo = envelope.resultInfo else {
                throw ProviderCanaryBackendError.invalidResponse
            }
            guard resultInfo.page < resultInfo.totalPages else {
                return records
            }
            page = resultInfo.page + 1
        }
    }

    private func isRunRecord(_ name: String) -> Bool {
        ProviderCanaryOwnerMatcher.isRunRecord(
            name,
            zoneName: configuration.zoneName,
            runPrefix: configuration.runPrefix
        )
    }

    private func delete(record: CloudflareCanaryRecord, zoneID: String) async throws {
        let _: CloudflareCanaryDeletedRecord = try await request(
            path: ["zones", zoneID, "dns_records", record.id],
            method: "DELETE"
        )
    }

    private func request<Result: Decodable>(
        path: [String],
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> Result {
        let envelope: CloudflareCanaryEnvelope<Result> = try await requestEnvelope(
            path: path,
            method: method,
            queryItems: queryItems
        )
        guard envelope.success, let result = envelope.result else {
            throw ProviderCanaryBackendError.invalidResponse
        }
        return result
    }

    private func requestEnvelope<Result: Decodable>(
        path: [String],
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> CloudflareCanaryEnvelope<Result> {
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
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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

        return try JSONDecoder().decode(CloudflareCanaryEnvelope<Result>.self, from: data)
    }

    private static func deletionOrder(
        _ lhs: CloudflareCanaryRecord,
        _ rhs: CloudflareCanaryRecord
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

    private static func timestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct CloudflareCanaryEnvelope<Result: Decodable>: Decodable {
    let success: Bool
    let result: Result?
    let resultInfo: CloudflareCanaryResultInfo?

    private enum CodingKeys: String, CodingKey {
        case success, result
        case resultInfo = "result_info"
    }
}

private struct CloudflareCanaryResultInfo: Decodable {
    let page: Int
    let totalPages: Int

    private enum CodingKeys: String, CodingKey {
        case page
        case totalPages = "total_pages"
    }
}

private struct CloudflareCanaryZone: Decodable {
    let id: String
    let name: String
}

private struct CloudflareCanaryRecord: Decodable {
    let id: String
    let name: String
    let type: String
    let content: String
    let priority: Int?
    let comment: String?
    let ttl: Int?
    let createdOn: String?

    var liveRecord: ProviderCanaryLiveRecord {
        ProviderCanaryLiveRecord(
            name: name,
            type: type,
            content: content,
            priority: priority,
            comment: comment,
            ttl: ttl
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, content, priority, comment, ttl
        case createdOn = "created_on"
    }
}

private struct CloudflareCanaryDeletedRecord: Decodable {
    let id: String
}
