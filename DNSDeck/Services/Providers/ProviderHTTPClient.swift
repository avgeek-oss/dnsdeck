import AvgeekNetworking
import Foundation

enum ProviderRetryPolicy {
    case never
    case transientRead(maxAttempts: Int = 3)
    case idempotentWrite(maxAttempts: Int = 3)
    case transientResponseWrite(maxAttempts: Int = 3)
}

enum ProviderAPIError: LocalizedError {
    case missingCredential(provider: DNSProvider, field: String)
    case invalidURL(provider: DNSProvider)
    case untrustedURL(provider: DNSProvider, url: URL)
    case invalidResponse(provider: DNSProvider)
    case http(
        provider: DNSProvider,
        statusCode: Int,
        message: String?,
        requestId: String?,
        retryAfter: TimeInterval?
    )
    case decoding(provider: DNSProvider, message: String)
    case invalidRecordContent(provider: DNSProvider, type: String, message: String)
    case actionFailed(provider: DNSProvider, actionId: Int64, code: String?, message: String?)
    case actionTimedOut(provider: DNSProvider, actionId: Int64)
    case operationFailed(provider: DNSProvider, operation: String, message: String?)
    case operationTimedOut(provider: DNSProvider, operation: String)

    var errorDescription: String? {
        switch self {
        case let .missingCredential(provider, field):
            "\(provider.displayName) \(field) is missing."
        case let .invalidURL(provider):
            "\(provider.displayName) returned an invalid API URL."
        case let .untrustedURL(provider, _):
            "\(provider.displayName) returned an untrusted pagination URL."
        case let .invalidResponse(provider):
            "\(provider.displayName) returned an invalid HTTP response."
        case let .http(provider, statusCode, message, requestId, _):
            [
                message ?? "\(provider.displayName) request failed with HTTP \(statusCode).",
                requestId.map { "Request ID: \($0)" },
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        case let .decoding(provider, message):
            "Unable to read the \(provider.displayName) response: \(message)"
        case let .invalidRecordContent(provider, type, message):
            "\(provider.displayName) \(type) record is invalid: \(message)"
        case let .actionFailed(provider, actionId, code, message):
            "\(provider.displayName) action \(actionId) failed: \(message ?? code ?? "unknown error")"
        case let .actionTimedOut(provider, actionId):
            "\(provider.displayName) action \(actionId) did not finish before the timeout."
        case let .operationFailed(provider, operation, message):
            "\(provider.displayName) \(operation) failed: \(message ?? "unknown error")"
        case let .operationTimedOut(provider, operation):
            "\(provider.displayName) \(operation) did not finish before the timeout."
        }
    }
}

struct ProviderHTTPResponse {
    let data: Data
    let response: HTTPURLResponse
}

final class ProviderHTTPClient {
    typealias Sleep = (TimeInterval) async throws -> Void
    static let liveSleep: Sleep = {
        try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000))
    }

    let provider: DNSProvider
    let baseURL: URL

    private let transport: any NetworkTransport
    private let defaultHeaders: () throws -> [String: String]
    private let sleep: Sleep
    private let now: () -> Date
    private let retryDelays = RetryDelayPolicy(
        baseDelay: 1,
        multiplier: 2,
        maximumBackoffDelay: 8,
        maximumServerDelay: 60
    )

    init(
        provider: DNSProvider,
        baseURL: URL,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        defaultHeaders: @escaping () throws -> [String: String] = { [:] },
        sleep: @escaping Sleep = liveSleep,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.transport = transport
        self.defaultHeaders = defaultHeaders
        self.sleep = sleep
        self.now = now
    }

    func url(pathComponents: [String], queryItems: [URLQueryItem] = []) throws -> URL {
        var url = baseURL
        for component in pathComponents {
            url.appendPathComponent(component)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ProviderAPIError.invalidURL(provider: provider)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let resolvedURL = components.url else {
            throw ProviderAPIError.invalidURL(provider: provider)
        }
        return resolvedURL
    }

    func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              url.host?.lowercased() == baseURL.host?.lowercased(),
              effectivePort(for: url) == effectivePort(for: baseURL)
        else {
            return false
        }
        return true
    }

    func send(
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        try await send(
            method: method,
            url: url(pathComponents: pathComponents, queryItems: queryItems),
            headers: headers,
            body: body,
            retryPolicy: retryPolicy
        )
    }

    func send(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        guard isTrusted(url) else {
            throw ProviderAPIError.untrustedURL(provider: provider, url: url)
        }

        let httpMethod = HTTPMethod(method)
        let isRead = httpMethod == .get || httpMethod == .head
        let maxAttempts: Int = switch retryPolicy {
        case .never: 1
        case let .transientRead(maxAttempts): isRead ? max(1, maxAttempts) : 1
        case let .idempotentWrite(maxAttempts): isRead ? 1 : max(1, maxAttempts)
        case let .transientResponseWrite(maxAttempts): isRead ? 1 : max(1, maxAttempts)
        }
        let retriesTransportFailures = if case .idempotentWrite = retryPolicy { true } else { false }

        var attempt = 1
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            for (name, value) in try defaultHeaders().merging(headers, uniquingKeysWith: { _, explicit in explicit }) {
                request.setValue(value, forHTTPHeaderField: name)
            }

            do {
                let (data, response) = try await transport.send(request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ProviderAPIError.invalidResponse(provider: provider)
                }

                guard (200 ..< 300).contains(httpResponse.statusCode) else {
                    let error = apiError(from: data, response: httpResponse)
                    if attempt < maxAttempts,
                       shouldRetryResponse(
                           statusCode: httpResponse.statusCode,
                           data: data,
                           policy: retryPolicy
                       )
                    {
                        try await sleep(retryDelay(for: httpResponse, attempt: attempt))
                        attempt += 1
                        continue
                    }
                    throw error
                }

                return ProviderHTTPResponse(data: data, response: httpResponse)
            } catch let error as ProviderAPIError {
                throw error
            } catch {
                if attempt < maxAttempts, retriesTransportFailures, shouldRetry(error: error) {
                    try await sleep(backoffDelay(attempt: attempt))
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }

    func decode<Response: Decodable>(_ type: Response.Type, from response: ProviderHTTPResponse) throws -> Response {
        do {
            return try JSONDecoder().decode(type, from: response.data)
        } catch {
            throw ProviderAPIError.decoding(provider: provider, message: error.localizedDescription)
        }
    }

    func paginate<State: Hashable, Item>(
        from initialState: State,
        page: (State) async throws -> (items: [Item], next: State?)
    ) async throws -> [Item] {
        var items: [Item] = []
        var state: State? = initialState
        var visited: Set<State> = []
        while let current = state {
            guard visited.insert(current).inserted, visited.count <= 1000 else {
                throw ProviderAPIError.invalidURL(provider: provider)
            }
            let result = try await page(current)
            items.append(contentsOf: result.items)
            state = result.next
        }
        return items
    }

    private func effectivePort(for url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    private func shouldRetryResponse(
        statusCode: Int,
        data: Data,
        policy: ProviderRetryPolicy
    ) -> Bool {
        switch policy {
        case .never:
            false
        case .transientRead, .idempotentWrite:
            [408, 425, 429, 500, 502, 503, 504].contains(statusCode)
        case .transientResponseWrite:
            statusCode == 429 || (statusCode == 409 && isPendingOperationConflict(data: data))
        }
    }

    private func isPendingOperationConflict(data: Data) -> Bool {
        guard let body = try? JSONDecoder().decode(ProviderJSONValue.self, from: data) else {
            return false
        }
        let code = body["error"]?.firstString("code") ?? body.firstString("code")
        let message = body["error"]?.firstString("message") ?? body.firstString("message")
        return code?.caseInsensitiveCompare("Conflict") == .orderedSame &&
            message?.localizedCaseInsensitiveContains("operation is pending") == true
    }

    private func shouldRetry(error: Error) -> Bool {
        TransientNetworkFailure.contains(error)
    }

    private func retryDelay(for response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        let serverDelay = ServerRetryDelay.parse(
            headers: HTTPHeaders(response.allHeaderFields),
            now: now(),
            resetHeader: "X-RateLimit-Reset"
        )
        return retryDelays.delay(
            retryNumber: max(0, attempt - 1),
            serverSuggestedDelay: serverDelay
        )
    }

    private func backoffDelay(attempt: Int) -> TimeInterval {
        retryDelays.exponentialDelay(retryNumber: max(0, attempt - 1))
    }

    private func apiError(from data: Data, response: HTTPURLResponse) -> ProviderAPIError {
        let body = try? JSONDecoder().decode(ProviderJSONValue.self, from: data)
        let requestIdCandidates: [String?] = [
            body?.firstString("requestId", "request_id", "correlation_id"),
            response.value(forHTTPHeaderField: "X-Request-ID"),
            response.value(forHTTPHeaderField: "X-Correlation-Id"),
            response.value(forHTTPHeaderField: "x-ms-request-id"),
            response.value(forHTTPHeaderField: "opc-request-id"),
            response.value(forHTTPHeaderField: "spaceship-operation-id"),
        ]
        let requestId = requestIdCandidates.compactMap { $0 }.first
        let retryAfter = ServerRetryDelay.parse(
            headers: HTTPHeaders(response.allHeaderFields),
            now: now(),
            resetHeader: "X-RateLimit-Reset"
        )

        return .http(
            provider: provider,
            statusCode: response.statusCode,
            message: body?.resolvedProviderMessage,
            requestId: requestId,
            retryAfter: retryAfter
        )
    }
}

private extension ProviderJSONValue {
    subscript(key: String) -> Self? {
        guard case let .object(values) = self else { return nil }
        return values[key]
    }

    var scalarString: String? {
        switch self {
        case let .string(value): value
        case let .number(value): value.rounded() == value ? String(Int(value)) : String(value)
        default: nil
        }
    }

    func firstString(_ keys: String...) -> String? {
        keys.lazy.compactMap { self[$0]?.scalarString }.first
    }

    var detailMessages: [String] {
        switch self {
        case let .array(values):
            values.compactMap { $0.fieldMessage ?? $0.scalarString }
        case let .object(values):
            values.keys.sorted().flatMap { field in
                values[field, default: .null].detailMessages.map { "\(field): \($0)" }
            }
        default:
            scalarString.map { [$0] } ?? []
        }
    }

    var fieldMessage: String? {
        guard let detail = firstString("reason", "message", "details") else { return nil }
        return firstString("field", "path").map { "\($0): \(detail)" } ?? detail
    }

    var resolvedProviderMessage: String? {
        if case let .array(values) = self {
            return values.compactMap(\.resolvedProviderMessageWithCode).nilIfEmpty?
                .joined(separator: "\n")
        }
        let fields = self["errors"]?.detailMessages ?? self["fields"]?.detailMessages ??
            self["data"]?.detailMessages
        let resolvedDetails = self["details"]?.detailMessages.nilIfEmpty?.joined(separator: "\n") ??
            fields?.nilIfEmpty?.joined(separator: "\n")
        let nestedError = self["error"]
        let rootMessage = firstString("message", "detail", "error_description") ??
            nestedError?.scalarString ?? nestedError?.firstString("message")
        let primary: String? = if let rootMessage, let resolvedDetails {
            "\(rootMessage)\n\(resolvedDetails)"
        } else {
            rootMessage ?? resolvedDetails ?? firstString("code") ??
                nestedError?.firstString("code") ?? firstString("id")
        }
        guard let nextAction = self["next_action"],
              let hint = nextAction.firstString("hint")
        else { return primary }
        let action = nextAction.firstString("url").map { "\(hint) (\($0))" } ?? hint
        return primary.map { "\($0)\n\(action)" } ?? action
    }

    var resolvedProviderMessageWithCode: String? {
        if let code = firstString("code"), let message = firstString("message") {
            return "\(code): \(message)"
        }
        return resolvedProviderMessage
    }
}

private extension Array {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
