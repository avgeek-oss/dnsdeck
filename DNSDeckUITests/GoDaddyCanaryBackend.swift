import Foundation

struct GoDaddyCanaryBackend: ProviderCanaryBackend {
    private let configuration: ProviderCanaryConfiguration
    private let shopperId: String?
    private let token: String
    private let baseURL = URL(string: "https://api.godaddy.com")!

    init(configuration: ProviderCanaryConfiguration) throws {
        self.configuration = configuration
        token = try configuration.credential("token")
        shopperId = try? configuration.credential("shopperId")
    }

    func deleteStaleRecords(olderThan cutoff: Date) async throws -> Int {
        let staleRecords = try await records().filter { record in
            let name = record.fullyQualifiedName(zoneName: configuration.zoneName)
            guard !isRunRecord(name),
                  ProviderCanaryOwnerMatcher.isTestRecord(
                      name,
                      zoneName: configuration.zoneName
                  ),
                  let creationDate = ProviderCanaryOwnerMatcher.creationDate(
                      name,
                      zoneName: configuration.zoneName
                  )
            else {
                return false
            }
            return creationDate < cutoff
        }
        try await delete(recordSets: staleRecords)
        return staleRecords.count
    }

    func deleteRunRecordsIfPresent() async throws -> Int {
        let records = try await matchingRunRecords()
        try await delete(recordSets: records)
        try await ProviderCanaryCleanup.assertRunRecordsAbsent {
            try await matchingRunRecords().map {
                $0.liveRecord(zoneName: configuration.zoneName)
            }
        }
        return records.count
    }

    func runRecords() async throws -> [ProviderCanaryLiveRecord] {
        try await matchingRunRecords().map {
            $0.liveRecord(zoneName: configuration.zoneName)
        }
    }

    private func matchingRunRecords() async throws -> [GoDaddyCanaryRecord] {
        try await records().filter {
            isRunRecord($0.fullyQualifiedName(zoneName: configuration.zoneName))
        }
    }

    private func records() async throws -> [GoDaddyCanaryRecord] {
        let limit = 500
        var records: [GoDaddyCanaryRecord] = []
        var offset = 0

        while offset <= 500_000 {
            let page: [GoDaddyCanaryRecord] = try await request(
                path: ["v1", "domains", configuration.zoneName, "records"],
                queryItems: [
                    URLQueryItem(name: "offset", value: String(offset)),
                    URLQueryItem(name: "limit", value: String(limit)),
                ]
            )
            records += page
            guard page.count == limit else { return records }
            offset += page.count
        }

        throw ProviderCanaryBackendError.invalidResponse
    }

    private func isRunRecord(_ name: String) -> Bool {
        ProviderCanaryOwnerMatcher.isRunRecord(
            name,
            zoneName: configuration.zoneName,
            runPrefix: configuration.runPrefix
        )
    }

    private func delete(recordSets: [GoDaddyCanaryRecord]) async throws {
        let identities = Set(recordSets.map(\.identity))
        for identity in identities {
            let _: Data = try await requestData(
                path: [
                    "v1",
                    "domains",
                    configuration.zoneName,
                    "records",
                    identity.type,
                    identity.name,
                ],
                method: "DELETE"
            )
        }
    }

    private func request<Result: Decodable>(
        path: [String],
        queryItems: [URLQueryItem] = []
    ) async throws -> Result {
        let data = try await requestData(path: path, queryItems: queryItems)
        return try JSONDecoder().decode(Result.self, from: data)
    }

    private func requestData(
        path: [String],
        method: String = "GET",
        queryItems: [URLQueryItem] = []
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
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let shopperId {
            request.setValue(shopperId, forHTTPHeaderField: "X-Shopper-Id")
        }

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
}

private struct GoDaddyCanaryRecord: Decodable {
    let type: String
    let name: String
    let data: String
    let ttl: Int?
    let priority: Int?

    var identity: GoDaddyCanaryRecordIdentity {
        GoDaddyCanaryRecordIdentity(type: type, name: name)
    }

    func fullyQualifiedName(zoneName: String) -> String {
        let normalizedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if normalizedName.isEmpty || normalizedName == "@" {
            return zoneName
        }
        if normalizedName.caseInsensitiveCompare(zoneName) == .orderedSame ||
            normalizedName.lowercased().hasSuffix(".\(zoneName.lowercased())")
        {
            return normalizedName
        }
        return "\(normalizedName).\(zoneName)"
    }

    func liveRecord(zoneName: String) -> ProviderCanaryLiveRecord {
        let normalizedType = type.uppercased()
        return ProviderCanaryLiveRecord(
            name: fullyQualifiedName(zoneName: zoneName),
            type: normalizedType,
            content: normalizedType == "TXT"
                ? ProviderCanaryContent.parseQuotedTXT(data)
                : data,
            priority: ["MX", "SRV"].contains(normalizedType) ? priority : nil,
            comment: nil,
            ttl: ttl
        )
    }
}

private struct GoDaddyCanaryRecordIdentity: Hashable {
    let type: String
    let name: String
}
