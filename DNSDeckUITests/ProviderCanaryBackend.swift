import Foundation

protocol ProviderCanaryBackend: Sendable {
    func deleteStaleRecords(olderThan cutoff: Date) async throws -> Int
    func deleteRunRecordsIfPresent() async throws -> Int
    func prepareRunRecords() async throws
    func runRecords() async throws -> [ProviderCanaryLiveRecord]
}

extension ProviderCanaryBackend {
    func prepareRunRecords() async throws {}
}

enum ProviderCanaryBackendFactory {
    static func make(
        configuration: ProviderCanaryConfiguration
    ) throws -> any ProviderCanaryBackend {
        switch configuration.definition.backendKind {
        case .cloudflare:
            try CloudflareCanaryBackend(configuration: configuration)
        case .goDaddy:
            try GoDaddyCanaryBackend(configuration: configuration)
        case .ionos:
            try IONOSCanaryBackend(configuration: configuration)
        case .route53:
            try Route53CanaryBackend(configuration: configuration)
        }
    }
}

enum ProviderCanaryBackendError: LocalizedError {
    case actionFailed(provider: String, actionID: Int64)
    case actionTimedOut(provider: String, actionID: Int64)
    case invalidResponse
    case invalidURL
    case providerRejected(provider: String, message: String)
    case recordsStillPresent
    case requestFailed(provider: String, statusCode: Int)
    case zoneNotFound(provider: String, zone: String)

    var errorDescription: String? {
        switch self {
        case let .actionFailed(provider, actionID):
            "\(provider) action \(actionID) failed."
        case let .actionTimedOut(provider, actionID):
            "\(provider) action \(actionID) did not finish before the canary timeout."
        case .invalidResponse:
            "The provider returned an invalid canary response."
        case .invalidURL:
            "The provider canary could not construct its request URL."
        case let .providerRejected(provider, message):
            "\(provider) rejected a canary request: \(message)"
        case .recordsStillPresent:
            "The provider still contains run-owned records after cleanup."
        case let .requestFailed(provider, statusCode):
            "\(provider) rejected a canary request with HTTP \(statusCode)."
        case let .zoneNotFound(provider, zone):
            "\(provider) did not return the configured canary zone \(zone)."
        }
    }
}

enum ProviderCanaryCleanup {
    static func assertRunRecordsAbsent(
        using records: () async throws -> [ProviderCanaryLiveRecord]
    ) async throws {
        for attempt in 0 ..< 5 {
            if try await records().isEmpty {
                return
            }
            guard attempt < 4 else {
                throw ProviderCanaryBackendError.recordsStillPresent
            }
            try await Task.sleep(for: .seconds(2))
        }
    }
}

enum ProviderCanaryContent {
    static func parseQuotedTXT(_ value: String) -> String {
        guard value.contains("\"") else { return value }
        var result = ""
        var isQuoted = false
        var isEscaped = false
        for character in value {
            if isEscaped {
                result.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isQuoted.toggle()
            } else if isQuoted {
                result.append(character)
            }
        }
        return result.isEmpty && value != "\"\"" ? value : result
    }
}
