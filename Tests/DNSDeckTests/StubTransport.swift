import Foundation
import XCTest
@testable import DNSDeckMCP

@MainActor
final class StubTransport: NetworkTransport {
    typealias Handler = (URLRequest, Int) throws -> (Data, URLResponse)
    private let handler: Handler
    private let limit: Int
    private(set) var requests: [URLRequest] = []

    init(limit: Int = 20, handler: @escaping Handler) {
        self.limit = limit
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard requests.count < limit else {
            XCTFail("Unexpected request beyond fixture limit of \(limit)")
            throw URLError(.resourceUnavailable)
        }
        requests.append(request)
        return try handler(request, requests.count - 1)
    }

    static func response(
        _ request: URLRequest,
        _ body: String = "{}",
        status: Int = 200,
        headers: [String: String] = [:]
    ) throws -> (Data, URLResponse) {
        try (
            Data(body.utf8),
            XCTUnwrap(HTTPURLResponse(
                url: XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: headers
            ))
        )
    }

    static func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    static func formBody(_ request: URLRequest) throws -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = try String(data: XCTUnwrap(request.httpBody), encoding: .utf8)
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}
