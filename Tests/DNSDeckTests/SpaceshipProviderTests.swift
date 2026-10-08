import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class SpaceshipProviderTests: XCTestCase {
    func testListDomainsUsesScopedHeadersAndOffsetPagination() async throws {
        let transport = SpaceshipRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/domains")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Secret"), "test-secret")
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                .queryItems ?? []
            XCTAssertEqual(query.first(where: { $0.name == "take" })?.value, "100")
            XCTAssertEqual(query.first(where: { $0.name == "skip" })?.value, String(index))
            XCTAssertEqual(query.first(where: { $0.name == "orderBy" })?.value, "name")
            return try Self.response(
                request: request,
                status: 200,
                body: "{\"items\":[{\"name\":\"page-\(index + 1).example\",\"unicodeName\":\"page-\(index + 1).example\"}],\"total\":2}"
            )
        }

        let domains = try await makeService(transport: transport).listDomains()

        XCTAssertEqual(domains.map(\.name), ["page-1.example", "page-2.example"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testListRecordsUsesMaximumPageSizeAndPreservesManagedGroups() async throws {
        let transport = SpaceshipRecordingTransport { request, _ in
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                .queryItems ?? []
            XCTAssertEqual(request.url?.path, "/api/v1/dns/records/example.com")
            XCTAssertEqual(query.first(where: { $0.name == "take" })?.value, "500")
            return try Self.response(request: request, status: 200, body: Self.recordsFixture)
        }

        let records = try await makeService(transport: transport).listRecords(domain: "example.com")
        let custom = ProviderRecord(provider: .spaceship, snapshot: records[0].snapshot(zoneName: "example.com"))
        let managed = ProviderRecord(provider: .spaceship, snapshot: records[1].snapshot(zoneName: "example.com"))

        XCTAssertEqual(custom.name, "www.example.com")
        XCTAssertEqual(custom.values, ["192.0.2.1"])
        XCTAssertTrue(custom.isEditable)
        XCTAssertEqual(managed.priority, 10)
        XCTAssertEqual(managed.values, ["mail.example.com."])
        XCTAssertFalse(managed.isEditable)
        XCTAssertNotNil(records[0].snapshot(zoneName: "example.com").providerData)
    }

    func testSaveAndDeleteUseDocumentedValueBasedPayloads() async throws {
        let mutation = try XCTUnwrap(
            CreateProviderRecordRequest(
                name: "www.example.com",
                type: "A",
                content: "192.0.2.1",
                ttl: 600,
                proxied: nil,
                priority: nil,
                comment: nil
            ).toSpaceshipMutations(zoneName: "example.com").first
        )
        let transport = SpaceshipRecordingTransport { request, index in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Secret"), "test-secret")
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "PUT")
                let body = try JSONDecoder().decode(
                    SpaceshipSaveRecordsRequest.self,
                    from: XCTUnwrap(request.httpBody)
                )
                XCTAssertFalse(body.force)
                XCTAssertEqual(body.items, [mutation])
            } else {
                XCTAssertEqual(request.httpMethod, "DELETE")
                let body = try JSONDecoder().decode(
                    [SpaceshipRecordMutation].self,
                    from: XCTUnwrap(request.httpBody)
                )
                XCTAssertEqual(body, [mutation.replacingTTL(nil)])
            }
            return try Self.response(request: request, status: 204, body: "")
        }
        let service = makeService(transport: transport)

        try await service.saveRecords(domain: "example.com", records: [mutation])
        try await service.deleteRecords(domain: "example.com", records: [mutation])

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testMutationsRespectMaximumBatchSize() async throws {
        let mutation = try XCTUnwrap(
            CreateProviderRecordRequest(
                name: "www.example.com",
                type: "A",
                content: "192.0.2.1",
                ttl: 600,
                proxied: nil,
                priority: nil,
                comment: nil
            ).toSpaceshipMutations(zoneName: "example.com").first
        )
        let transport = SpaceshipRecordingTransport { request, index in
            let body = try JSONDecoder().decode(
                SpaceshipSaveRecordsRequest.self,
                from: XCTUnwrap(request.httpBody)
            )
            XCTAssertEqual(body.items.count, index == 0 ? 500 : 1)
            return try Self.response(request: request, status: 204, body: "")
        }

        try await makeService(transport: transport).saveRecords(
            domain: "example.com",
            records: Array(repeating: mutation, count: 501)
        )

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testMissingSecretFailsBeforeSendingRequest() async throws {
        let transport = SpaceshipRecordingTransport { request, _ in
            XCTFail("Missing credentials must not reach the API")
            return try Self.response(request: request, status: 200, body: #"{"items":[],"total":0}"#)
        }
        let service = try SpaceshipService(
            credentialsProvider: { (apiKey: "test-key", apiSecret: "  ") },
            baseURL: XCTUnwrap(URL(string: "https://spaceship.test/api")),
            transport: transport,
            sleep: { _ in }
        )

        do {
            _ = try await service.listDomains()
            XCTFail("Expected missing credential error")
        } catch ProviderAPIError.missingCredential(.spaceship, "API secret") {}
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testMappingsCoverStructuredRecordShapesAndTTLLimits() throws {
        let caa = try CreateProviderRecordRequest(
            name: "@",
            type: "CAA",
            content: "128 issue letsencrypt.org",
            ttl: 10,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toSpaceshipMutations(zoneName: "example.com")[0]
        XCTAssertEqual(caa.name, "@")
        XCTAssertEqual(caa.flag, 128)
        XCTAssertEqual(caa.tag, "issue")
        XCTAssertEqual(caa.value, "letsencrypt.org")
        XCTAssertEqual(caa.ttl, 60)

        let srv = try CreateProviderRecordRequest(
            name: "_sip._tcp.example.com",
            type: "SRV",
            content: "10 5 443 sip.example.com.",
            ttl: 9999,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toSpaceshipMutations(zoneName: "example.com")[0]
        XCTAssertEqual(srv.name, "@")
        XCTAssertEqual(srv.service, "_sip")
        XCTAssertEqual(srv.protocol, "_tcp")
        XCTAssertEqual(srv.priority, 10)
        XCTAssertEqual(srv.weight, 5)
        XCTAssertEqual(srv.port, .number(443))
        XCTAssertEqual(srv.ttl, 3600)

        let https = try CreateProviderRecordRequest(
            name: "_8443._https.www.example.com",
            type: "HTTPS",
            content: "1 edge.example.net. alpn=h2",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toSpaceshipMutations(zoneName: "example.com")[0]
        XCTAssertEqual(https.name, "www")
        XCTAssertEqual(https.port, .label("_8443"))
        XCTAssertEqual(https.scheme, "_https")
        XCTAssertEqual(https.svcPriority, 1)
        XCTAssertEqual(https.targetName, "edge.example.net.")
        XCTAssertEqual(https.svcParams, "alpn=h2")

        let tlsa = try CreateProviderRecordRequest(
            name: "_443._tcp.www.example.com",
            type: "TLSA",
            content: "3 1 1 0123456789ABCDEF 0123456789ABCDEF 0123456789ABCDEF 0123456789ABCDEF",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toSpaceshipMutations(zoneName: "example.com")[0]
        XCTAssertEqual(tlsa.name, "www")
        XCTAssertEqual(tlsa.port, .label("_443"))
        XCTAssertEqual(tlsa.protocol, "_tcp")
        XCTAssertEqual(tlsa.usage, 3)
        XCTAssertEqual(tlsa.selector, 1)
        XCTAssertEqual(tlsa.matching, 1)
        XCTAssertEqual(tlsa.associationData?.count, 64)
        XCTAssertEqual(
            tlsa.associationData,
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        )

        XCTAssertThrowsError(
            try CreateProviderRecordRequest(
                name: "_443._tcp.www.example.com",
                type: "TLSA",
                content: "3 1 1 not-hex",
                ttl: 300,
                proxied: nil,
                priority: nil,
                comment: nil
            ).toSpaceshipMutations(zoneName: "example.com")
        )
    }

    func testAdapterUsesTTLUpdateAndRollbackSafeReplacement() async throws {
        let transport = SpaceshipRecordingTransport { request, index in
            if index == 0 {
                let body = try JSONDecoder().decode(
                    SpaceshipSaveRecordsRequest.self,
                    from: XCTUnwrap(request.httpBody)
                )
                XCTAssertEqual(body.items[0].address, "192.0.2.2")
                return try Self.response(request: request, status: 204, body: "")
            }
            if index == 1 {
                XCTAssertEqual(request.httpMethod, "DELETE")
                return try Self.response(
                    request: request,
                    status: 422,
                    body: #"{"detail":"temporary failure"}"#
                )
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            let rollback = try JSONDecoder().decode(
                [SpaceshipRecordMutation].self,
                from: XCTUnwrap(request.httpBody)
            )
            XCTAssertEqual(rollback[0].address, "192.0.2.2")
            return try Self.response(request: request, status: 204, body: "")
        }
        let adapter = SpaceshipDNSProviderService(service: makeService(transport: transport))

        do {
            try await adapter.updateRecord(
                in: providerZone(),
                record: providerRecord(),
                edits: UpdateProviderRecordRequest(content: "192.0.2.2", ttl: 600)
            )
            XCTFail("Expected delete failure")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .spaceship)
            XCTAssertEqual(statusCode, 422)
            XCTAssertEqual(message, "temporary failure")
        }
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testTTLOnlyUpdateDoesNotDeleteRecord() async throws {
        let transport = SpaceshipRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "PUT")
            let body = try JSONDecoder().decode(
                SpaceshipSaveRecordsRequest.self,
                from: XCTUnwrap(request.httpBody)
            )
            XCTAssertEqual(body.items[0].address, "192.0.2.1")
            XCTAssertEqual(body.items[0].ttl, 1200)
            return try Self.response(request: request, status: 204, body: "")
        }
        let adapter = SpaceshipDNSProviderService(service: makeService(transport: transport))

        try await adapter.updateRecord(
            in: providerZone(),
            record: providerRecord(),
            edits: UpdateProviderRecordRequest(ttl: 1200)
        )

        XCTAssertEqual(transport.requests.count, 1)
    }

    func testManagedRecordCannotBeDeleted() async throws {
        let transport = SpaceshipRecordingTransport { request, _ in
            XCTFail("Managed records must not reach the API")
            return try Self.response(request: request, status: 204, body: "")
        }
        let adapter = SpaceshipDNSProviderService(service: makeService(transport: transport))
        let native = try Self.decodeRecord(Self.managedRecordFixture)
        let record = ProviderRecord(provider: .spaceship, snapshot: native.snapshot(zoneName: "example.com"))

        do {
            try await adapter.deleteRecord(in: providerZone(), record: record)
            XCTFail("Expected read-only record error")
        } catch ProviderOperationError.readOnlyRecord(.spaceship, _) {}
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testValidationErrorAndOperationIDArePreserved() async throws {
        let transport = SpaceshipRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 422,
                body: #"{"detail":"Validation failed","data":[{"field":"items[0].ttl","details":"Must be at most 3600"}]}"#,
                headers: ["spaceship-operation-id": "operation-123"]
            )
        }
        let mutation = try CreateProviderRecordRequest(
            name: "www",
            type: "A",
            content: "192.0.2.1",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toSpaceshipMutations(zoneName: "example.com")

        do {
            try await makeService(transport: transport).saveRecords(domain: "example.com", records: mutation)
            XCTFail("Expected validation error")
        } catch let ProviderAPIError.http(provider, statusCode, message, requestId, _) {
            XCTAssertEqual(provider, .spaceship)
            XCTAssertEqual(statusCode, 422)
            XCTAssertEqual(message, "Validation failed\nitems[0].ttl: Must be at most 3600")
            XCTAssertEqual(requestId, "operation-123")
        }
    }

    func testPaginationRejectsEmptyPageBeforeReportedTotal() async throws {
        let transport = SpaceshipRecordingTransport { request, _ in
            try Self.response(request: request, status: 200, body: #"{"items":[],"total":1}"#)
        }

        do {
            _ = try await makeService(transport: transport).listDomains()
            XCTFail("Expected unsafe pagination failure")
        } catch ProviderAPIError.invalidURL(.spaceship) {}
    }

    private func makeService(transport: SpaceshipRecordingTransport) -> SpaceshipService {
        SpaceshipService(
            credentialsProvider: { (apiKey: "test-key", apiSecret: "test-secret") },
            baseURL: URL(string: "https://spaceship.test/api")!,
            transport: transport,
            sleep: { _ in }
        )
    }

    private func providerZone() throws -> ProviderZone {
        let domain = try JSONDecoder().decode(
            SpaceshipDomain.self,
            from: Data(#"{"name":"example.com","unicodeName":"example.com"}"#.utf8)
        )
        return ProviderZone(provider: .spaceship, snapshot: domain.snapshot(), environmentId: UUID())
    }

    private func providerRecord() throws -> ProviderRecord {
        let native = try Self.decodeRecord(Self.customRecordFixture)
        return ProviderRecord(provider: .spaceship, snapshot: native.snapshot(zoneName: "example.com"))
    }

    private static func decodeRecord(_ fixture: String) throws -> SpaceshipDNSRecord {
        try JSONDecoder().decode(SpaceshipDNSRecord.self, from: Data(fixture.utf8))
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) throws -> (Data, URLResponse) {
        var responseHeaders = headers
        responseHeaders["Content-Type"] = status >= 400 ? "application/problem+json" : "application/json"
        return try (
            Data(body.utf8),
            XCTUnwrap(
                HTTPURLResponse(
                    url: XCTUnwrap(request.url),
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: responseHeaders
                )
            )
        )
    }

    private static let customRecordFixture =
        #"{"type":"A","name":"www","ttl":300,"group":{"type":"custom"},"address":"192.0.2.1"}"#
    private static let managedRecordFixture =
        #"{"type":"MX","name":"@","ttl":3600,"group":{"type":"product"},"exchange":"mail.example.com.","preference":10}"#
    private static let recordsFixture =
        "{\"items\":[\(customRecordFixture),\(managedRecordFixture)],\"total\":2}"
}

@MainActor
private final class SpaceshipRecordingTransport: NetworkTransport {
    typealias Handler = (URLRequest, Int) throws -> (Data, URLResponse)

    private let handler: Handler
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return try handler(request, requests.count - 1)
    }
}
