import AvgeekNetworking
import XCTest

final class NetworkingTests: XCTestCase {
    func testHTTPMethodsExposeSafetyAndIdempotency() {
        XCTAssertTrue(HTTPMethod.get.isSafe)
        XCTAssertTrue(HTTPMethod.head.isSafe)
        XCTAssertTrue(HTTPMethod.put.isIdempotent)
        XCTAssertTrue(HTTPMethod.delete.isIdempotent)
        XCTAssertFalse(HTTPMethod.post.isSafe)
        XCTAssertFalse(HTTPMethod.post.isIdempotent)
        XCTAssertFalse(HTTPMethod.patch.isIdempotent)
    }

    func testHeadersAreCaseInsensitive() {
        let headers = HTTPHeaders(["Retry-After": "5", "X-Request-ID": "request-1"])

        XCTAssertEqual(headers["retry-after"], "5")
        XCTAssertEqual(headers["X-REQUEST-ID"], "request-1")
        XCTAssertEqual(headers.dictionary["x-request-id"], "request-1")
    }

    func testRetryPolicyBoundsServerAndExponentialDelays() {
        let policy = RetryDelayPolicy(
            baseDelay: 1,
            multiplier: 2,
            maximumBackoffDelay: 8,
            maximumServerDelay: 60
        )

        XCTAssertEqual(policy.exponentialDelay(retryNumber: 0), 1)
        XCTAssertEqual(policy.exponentialDelay(retryNumber: 3), 8)
        XCTAssertEqual(policy.exponentialDelay(retryNumber: 20), 8)
        XCTAssertEqual(policy.delay(retryNumber: 0, serverSuggestedDelay: 120), 60)
        XCTAssertEqual(policy.delay(retryNumber: 1, serverSuggestedDelay: -5), 0)
        XCTAssertEqual(policy.delay(retryNumber: 1, serverSuggestedDelay: .infinity), 2)
        XCTAssertEqual(policy.nanoseconds(retryNumber: 0, serverSuggestedDelay: 0.5), 500_000_000)
    }

    func testRetryPolicyCannotOverflowNanosecondConversion() {
        let policy = RetryDelayPolicy(
            baseDelay: .infinity,
            multiplier: .infinity,
            maximumBackoffDelay: .infinity,
            maximumServerDelay: .infinity
        )

        XCTAssertEqual(policy.nanoseconds(retryNumber: .max), UInt64.max / 1_000_000_000 * 1_000_000_000)
        XCTAssertEqual(policy.delay(retryNumber: 0, serverSuggestedDelay: .nan), policy.maximumBackoffDelay)
    }

    func testRetryAfterParsesSecondsDateAndEpochReset() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-14T00:00:00Z"))

        XCTAssertEqual(
            ServerRetryDelay.parse(headers: HTTPHeaders(["retry-after": "7"]), now: now),
            7
        )
        XCTAssertEqual(
            ServerRetryDelay.parse(
                headers: HTTPHeaders(["Retry-After": "Tue, 14 Jul 2026 00:00:11 GMT"]),
                now: now
            ),
            11
        )
        XCTAssertEqual(
            ServerRetryDelay.parse(
                headers: HTTPHeaders(["X-RateLimit-Reset": "1783987213"]),
                now: now,
                resetHeader: "X-RateLimit-Reset"
            ),
            13
        )
    }

    func testTransientNetworkFailureClassification() {
        XCTAssertTrue(TransientNetworkFailure.contains(URLError(.timedOut)))
        XCTAssertTrue(TransientNetworkFailure.contains(URLError(.networkConnectionLost)))
        XCTAssertFalse(TransientNetworkFailure.contains(URLError(.badURL)))
        XCTAssertFalse(TransientNetworkFailure.contains(TestError.example))
    }

    func testSessionConfigurationAppliesCallerPolicy() {
        let configuration = HTTPSessionConfiguration.make(options: HTTPSessionOptions(
            storagePolicy: .ephemeral,
            requestTimeout: 30,
            resourceTimeout: 90,
            cachePolicy: .reloadIgnoringLocalCacheData,
            usesURLCache: false,
            maximumConnectionsPerHost: 4,
            waitsForConnectivity: true,
            additionalHeaders: ["User-Agent": "TestApp/1.0"]
        ))

        XCTAssertEqual(configuration.timeoutIntervalForRequest, 30)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 90)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 4)
        XCTAssertTrue(configuration.waitsForConnectivity)
        XCTAssertEqual(configuration.httpAdditionalHeaders?["User-Agent"] as? String, "TestApp/1.0")
    }

    func testSessionConfigurationPreservesUnspecifiedPlatformDefaults() {
        let baseline = URLSessionConfiguration.ephemeral
        let configuration = HTTPSessionConfiguration.make(options: HTTPSessionOptions(
            storagePolicy: .ephemeral,
            requestTimeout: 600,
            maximumConnectionsPerHost: 6
        ))

        XCTAssertEqual(configuration.timeoutIntervalForRequest, 600)
        XCTAssertEqual(configuration.timeoutIntervalForResource, baseline.timeoutIntervalForResource)
        XCTAssertEqual(configuration.requestCachePolicy, baseline.requestCachePolicy)
        XCTAssertEqual(configuration.waitsForConnectivity, baseline.waitsForConnectivity)
        XCTAssertEqual(configuration.urlCache == nil, baseline.urlCache == nil)
        XCTAssertEqual(configuration.urlCache?.memoryCapacity, baseline.urlCache?.memoryCapacity)
        XCTAssertEqual(configuration.urlCache?.diskCapacity, baseline.urlCache?.diskCapacity)
    }

    func testRedactedRequestRemovesSecretsButKeepsDiagnosticPath() throws {
        let url = try XCTUnwrap(URL(string: "https://user:secret@example.com/v1/models?api_key=secret#token"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let redacted = RedactedHTTPRequest(request: request)

        XCTAssertEqual(redacted.description, "POST https://example.com/v1/models")
        XCTAssertFalse(redacted.description.contains("secret"))
        XCTAssertFalse(redacted.description.contains("api_key"))
    }
}

private enum TestError: Error {
    case example
}
