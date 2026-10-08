import Foundation

/// The smallest injectable boundary around URL loading.
public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// A validated HTTP response with case-insensitive headers.
public struct HTTPResponse: @unchecked Sendable {
    public let data: Data
    public let response: HTTPURLResponse
    public let headers: HTTPHeaders

    public init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
        headers = HTTPHeaders(response.allHeaderFields)
    }

    public var statusCode: Int {
        response.statusCode
    }
}

/// Stores headers using lowercase names so callers do not depend on server or
/// URLSession capitalization behavior.
public struct HTTPHeaders: Equatable, Sendable {
    private let values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = Dictionary(
            values.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { _, last in last }
        )
    }

    public init(_ values: [AnyHashable: Any]) {
        self.init(
            Dictionary(
                values.compactMap { key, value in
                    guard let key = key as? String else { return nil }
                    return (key, String(describing: value))
                },
                uniquingKeysWith: { _, last in last }
            )
        )
    }

    public subscript(name: String) -> String? {
        values[name.lowercased()]
    }

    public var dictionary: [String: String] {
        values
    }
}
