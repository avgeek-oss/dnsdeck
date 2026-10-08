import XCTest
@testable import DNSDeckMCP

@MainActor
final class ProviderHTTPClientTests: XCTestCase {
    func testUntrustedOriginsAreRejectedBeforeCredentialsOrTransport() async throws {
        let transport = StubTransport(limit: 0) { _, _ in throw URLError(.badURL) }
        let client = try ProviderHTTPClient(
            provider: .digitalOcean, baseURL: XCTUnwrap(URL(string: "https://api.example.test/v2")),
            transport: transport, defaultHeaders: {
                XCTFail("Credentials must not be resolved for untrusted URLs")
                return [:]
            }
        )
        for address in ["http://api.example.test/v2", "https://evil.example/v2", "https://api.example.test:444/v2"] {
            do {
                _ = try await client.send(method: "GET", url: XCTUnwrap(URL(string: address)))
                XCTFail("Expected untrusted origin")
            } catch ProviderAPIError.untrustedURL {}
        }
        XCTAssertTrue(try client.isTrusted(XCTUnwrap(URL(string: "https://api.example.test:443/v2"))))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testPaginationRejectsRepeatedCursorAndCapsUnendingUniquePages() async throws {
        let client = makeClient(StubTransport(limit: 0) { _, _ in throw URLError(.badURL) })
        for repeats in [true, false] {
            var pages = 0
            do {
                let _: [Int] = try await client.paginate(from: 0) { cursor in
                    pages += 1
                    return ([cursor], repeats ? 0 : cursor + 1)
                }
                XCTFail("Expected bounded pagination")
            } catch ProviderAPIError.invalidURL {}
            XCTAssertEqual(pages, repeats ? 1 : 1000)
        }
    }

    func testReadRetryIsBoundedAndClampsRetryAfter() async throws {
        var delays: [TimeInterval] = []
        let transport = StubTransport(limit: 3) { request, _ in
            try StubTransport.response(
                request,
                #"{"message":"Try later"}"#,
                status: 429,
                headers: ["Retry-After": "9999"]
            )
        }
        do {
            _ = try await makeClient(transport, sleep: { delays.append($0) })
                .send(method: "GET", pathComponents: ["zones"], retryPolicy: .transientRead())
            XCTFail("Expected exhausted retries")
        } catch let ProviderAPIError.http(_, status, _, _, _) {
            XCTAssertEqual(status, 429)
        }
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(delays, [60, 60])
    }

    func testNonIdempotentWritesNeverRetryAmbiguousTransportFailure() async throws {
        for policy: ProviderRetryPolicy in [.never, .transientRead(), .transientResponseWrite()] {
            let transport = StubTransport(limit: 1) { _, _ in throw URLError(.networkConnectionLost) }
            do {
                _ = try await makeClient(transport).send(
                    method: "POST",
                    pathComponents: ["records"],
                    retryPolicy: policy
                )
                XCTFail("Expected transport failure")
            } catch let error as URLError {
                XCTAssertEqual(error.code, .networkConnectionLost)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testIdempotentWriteRetriesWithIdenticalBodyAndHeaders() async throws {
        var delays: [TimeInterval] = []
        let body = Data(#"{"ttl":300}"#.utf8)
        let transport = StubTransport { request, index in
            XCTAssertEqual(request.httpBody, body)
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "etag-1")
            if index == 0 { throw URLError(.timedOut) }
            return try StubTransport.response(request)
        }
        _ = try await makeClient(transport, sleep: { delays.append($0) }).send(
            method: "PUT", pathComponents: ["record"], headers: ["If-Match": "etag-1"],
            body: body, retryPolicy: .idempotentWrite()
        )
        XCTAssertEqual(delays, [1])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testCancellationAndPermanentHTTPFailureDoNotRetry() async throws {
        for cancelled in [false, true] {
            let transport = StubTransport(limit: 1) { request, _ in
                if cancelled { throw CancellationError() }
                return try StubTransport.response(request, #"{"message":"Denied"}"#, status: 403)
            }
            do {
                _ = try await makeClient(transport).send(
                    method: "PUT",
                    pathComponents: ["record"],
                    retryPolicy: .idempotentWrite()
                )
                XCTFail("Expected failure")
            } catch is CancellationError {
                XCTAssertTrue(cancelled)
            } catch let ProviderAPIError.http(_, status, _, _, _) {
                XCTAssertEqual(status, 403)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testMalformedJSONAndNonHTTPResponsesHaveProviderContext() async throws {
        let transport = StubTransport { request, _ in
            try (
                Data(),
                URLResponse(
                    url: XCTUnwrap(request.url),
                    mimeType: nil,
                    expectedContentLength: 0,
                    textEncodingName: nil
                )
            )
        }
        let client = makeClient(transport)
        do {
            _ = try await client.send(method: "GET", pathComponents: [])
            XCTFail("Expected invalid response")
        } catch let ProviderAPIError.invalidResponse(provider) {
            XCTAssertEqual(provider, .digitalOcean)
        }
        let response = try XCTUnwrap(try HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://api.example.test")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        XCTAssertThrowsError(try client.decode(
            [String].self,
            from: .init(data: Data("{".utf8), response: response)
        )) { error in
            guard case ProviderAPIError.decoding(.digitalOcean, _) = error
            else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    private func makeClient(_ transport: StubTransport, sleep: @escaping ProviderHTTPClient.Sleep = { _ in
    }) -> ProviderHTTPClient {
        ProviderHTTPClient(
            provider: .digitalOcean,
            baseURL: URL(string: "https://api.example.test")!,
            transport: transport,
            sleep: sleep
        )
    }
}
