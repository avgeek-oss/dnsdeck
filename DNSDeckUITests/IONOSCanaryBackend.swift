import Foundation

struct IONOSCanaryBackend: ProviderCanaryBackend {
    private let apiKey: String
    private let configuration: ProviderCanaryConfiguration
    private let baseURL = URL(string: "https://api.hosting.ionos.com/dns")!

    init(configuration: ProviderCanaryConfiguration) throws {
        self.configuration = configuration
        apiKey = try configuration.credential("apiKey")
    }

    func deleteStaleRecords(olderThan cutoff: Date) async throws -> Int {
        let zone = try await customerZone()
        let staleRecords = zone.records.filter { record in
            guard !isRunRecord(record.name),
                  ProviderCanaryOwnerMatcher.isTestRecord(
                      record.name,
                      zoneName: configuration.zoneName
                  ),
                  let creationDate = ProviderCanaryOwnerMatcher.creationDate(
                      record.name,
                      zoneName: configuration.zoneName
                  )
            else {
                return false
            }
            return creationDate < cutoff
        }
        for record in staleRecords {
            try await delete(recordID: record.id, zoneID: zone.id)
        }
        return staleRecords.count
    }

    func deleteRunRecordsIfPresent() async throws -> Int {
        let zone = try await customerZone()
        let records = zone.records.filter { isRunRecord($0.name) }
        for record in records {
            try await delete(recordID: record.id, zoneID: zone.id)
        }
        try await ProviderCanaryCleanup.assertRunRecordsAbsent {
            try await matchingRunRecords().map(\.liveRecord)
        }
        return records.count
    }

    func runRecords() async throws -> [ProviderCanaryLiveRecord] {
        try await matchingRunRecords().map(\.liveRecord)
    }

    private func matchingRunRecords() async throws -> [IONOSCanaryRecord] {
        try await customerZone().records.filter { isRunRecord($0.name) }
    }

    private func customerZone() async throws -> IONOSCanaryCustomerZone {
        let zones: [IONOSCanaryZone] = try await request(path: ["v1", "zones"])
        guard let zone = zones.first(where: {
            $0.name.caseInsensitiveCompare(configuration.zoneName) == .orderedSame
        }) else {
            throw ProviderCanaryBackendError.zoneNotFound(
                provider: configuration.definition.displayName,
                zone: configuration.zoneName
            )
        }
        let customerZone: IONOSCanaryCustomerZone = try await request(
            path: ["v1", "zones", zone.id]
        )
        guard customerZone.name.caseInsensitiveCompare(configuration.zoneName) == .orderedSame else {
            throw ProviderCanaryBackendError.zoneNotFound(
                provider: configuration.definition.displayName,
                zone: configuration.zoneName
            )
        }
        return customerZone
    }

    private func isRunRecord(_ name: String) -> Bool {
        ProviderCanaryOwnerMatcher.isRunRecord(
            name,
            zoneName: configuration.zoneName,
            runPrefix: configuration.runPrefix
        )
    }

    private func delete(recordID: String, zoneID: String) async throws {
        let _: Data = try await requestData(
            path: ["v1", "zones", zoneID, "records", recordID],
            method: "DELETE",
            retriesTransientFailures: false
        )
    }

    private func request<Result: Decodable>(path: [String]) async throws -> Result {
        let data = try await requestData(
            path: path,
            method: "GET",
            retriesTransientFailures: true
        )
        return try JSONDecoder().decode(Result.self, from: data)
    }

    private func requestData(
        path: [String],
        method: String,
        retriesTransientFailures: Bool
    ) async throws -> Data {
        let requestURL = path.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        let maximumAttempts = retriesTransientFailures ? 4 : 1
        var lastStatusCode = 0

        for attempt in 0 ..< maximumAttempts {
            var request = URLRequest(url: requestURL)
            request.httpMethod = method
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError {
                guard attempt + 1 < maximumAttempts, isTransient(error) else {
                    throw error
                }
                try await Task.sleep(for: .seconds(backoffDelay(for: attempt)))
                continue
            }
            guard let response = response as? HTTPURLResponse else {
                throw ProviderCanaryBackendError.invalidResponse
            }
            lastStatusCode = response.statusCode

            if retriesTransientFailures,
               response.statusCode == 429 || (500 ..< 600).contains(response.statusCode)
            {
                guard attempt + 1 < maximumAttempts else { break }
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(TimeInterval.init)
                let delay = retryAfter ?? backoffDelay(for: attempt)
                try await Task.sleep(for: .seconds(min(60, max(1, delay))))
                continue
            }
            guard (200 ..< 300).contains(response.statusCode) else {
                throw ProviderCanaryBackendError.requestFailed(
                    provider: configuration.definition.displayName,
                    statusCode: response.statusCode
                )
            }
            return data
        }

        throw ProviderCanaryBackendError.requestFailed(
            provider: configuration.definition.displayName,
            statusCode: lastStatusCode
        )
    }

    private func backoffDelay(for attempt: Int) -> TimeInterval {
        TimeInterval(1 << attempt)
    }

    private func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .secureConnectionFailed:
            true
        default:
            false
        }
    }
}

private struct IONOSCanaryZone: Decodable {
    let id: String
    let name: String
}

private struct IONOSCanaryCustomerZone: Decodable {
    let id: String
    let name: String
    let records: [IONOSCanaryRecord]
}

private struct IONOSCanaryRecord: Decodable {
    let id: String
    let name: String
    let type: String
    let content: String
    let ttl: Int?
    let prio: Int?

    var liveRecord: ProviderCanaryLiveRecord {
        let normalizedType = type.uppercased()
        return ProviderCanaryLiveRecord(
            name: name.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            type: normalizedType,
            content: normalizedType == "TXT"
                ? ProviderCanaryContent.parseQuotedTXT(content)
                : content,
            priority: ["MX", "SRV"].contains(normalizedType) ? prio : nil,
            comment: nil,
            ttl: ttl
        )
    }
}
