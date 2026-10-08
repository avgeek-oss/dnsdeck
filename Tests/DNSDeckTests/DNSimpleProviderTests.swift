import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class DNSimpleProviderTests: XCTestCase {
    func testListZonesUsesAccountScopeBearerAuthAndPagination() async throws {
        let transport = DNSimpleRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dnsimple-token")
            XCTAssertEqual(request.url?.path, "/v2/1010/zones")
            let zone = Self.zoneJSON(id: index + 1, name: index == 0 ? "one.example" : "two.example")
            if index == 0 {
                XCTAssertEqual(request.url?.query, "page=1&per_page=100")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: "{\"data\":[\(zone)],\"pagination\":{\"current_page\":1,\"per_page\":100,\"total_entries\":2,\"total_pages\":2}}"
                )
            }
            XCTAssertEqual(request.url?.query, "page=2&per_page=100")
            return try Self.response(
                request: request,
                status: 200,
                body: "{\"data\":[\(zone)],\"pagination\":{\"current_page\":2,\"per_page\":100,\"total_entries\":2,\"total_pages\":2}}"
            )
        }

        let zones = try await makeService(transport: transport).listZones()

        XCTAssertEqual(zones.map(\.name), ["one.example", "two.example"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testZoneDetailsPreserveLifecycleAndNameservers() async throws {
        let transport = DNSimpleRecordingTransport { request, _ in
            XCTAssertEqual(request.url?.path, "/v2/1010/zones/example.com")
            return try Self.response(
                request: request,
                status: 200,
                body: "{\"data\":\(Self.zoneJSON(id: 42, name: "example.com"))}"
            )
        }

        let zone = try await makeService(transport: transport).getZone(name: "example.com")
        let snapshot = zone.snapshot(nameservers: DNSimpleService.nameservers)

        XCTAssertEqual(snapshot.id, "42")
        XCTAssertEqual(snapshot.status, "active")
        XCTAssertEqual(snapshot.nameservers, DNSimpleService.nameservers)
        XCTAssertNotNil(snapshot.providerData)
    }

    func testRecordCRUDScopesWritesToDNSimpleOnly() async throws {
        let create = DNSimpleRecordCreateRequest(
            name: "",
            type: "MX",
            content: "mail.example.com.",
            ttl: 600,
            priority: 10,
            integratedZones: ["dnsimple"]
        )
        let update = DNSimpleRecordUpdateRequest(
            name: "mail",
            content: "new.example.com.",
            ttl: 3600,
            priority: 20,
            integratedZones: ["dnsimple"]
        )
        let record = Self.recordJSON(id: 9, type: "MX", name: "", content: "mail.example.com.", priority: 10)
        let transport = DNSimpleRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v2/1010/zones/example.com/records")
                XCTAssertEqual(
                    try JSONDecoder().decode(DNSimpleRecordCreateRequest.self, from: XCTUnwrap(request.httpBody)),
                    create
                )
                return try Self.response(request: request, status: 201, body: "{\"data\":\(record)}")
            case 1:
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertEqual(request.url?.path, "/v2/1010/zones/example.com/records/9")
                XCTAssertEqual(
                    try JSONDecoder().decode(DNSimpleRecordUpdateRequest.self, from: XCTUnwrap(request.httpBody)),
                    update
                )
                return try Self.response(request: request, status: 200, body: "{\"data\":\(record)}")
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v2/1010/zones/example.com/records/9")
                return try Self.response(request: request, status: 204, body: "")
            }
        }
        let service = makeService(transport: transport)

        _ = try await service.createRecord(zoneName: "example.com", request: create)
        _ = try await service.updateRecord(zoneName: "example.com", recordId: 9, request: update)
        try await service.deleteRecord(zoneName: "example.com", recordId: 9)
    }

    func testRecordSnapshotsAndMappingKeepPriorityProviderSpecific() throws {
        let srv = try JSONDecoder().decode(
            DNSimpleZoneRecord.self,
            from: Data(Self.recordJSON(
                id: 10,
                type: "SRV",
                name: "_sip._tcp",
                content: "20 5060 sip.example.com.",
                priority: 10
            ).utf8)
        )
        XCTAssertEqual(srv.snapshot().content, "10 20 5060 sip.example.com.")
        XCTAssertEqual(srv.snapshot().priority, 10)

        let request = try CreateProviderRecordRequest(
            name: "_sip._tcp.example.com",
            type: "SRV",
            content: "10 20 5060 sip.example.com.",
            ttl: 600,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toDNSimpleRequest(zoneName: "example.com")
        XCTAssertEqual(request.name, "_sip._tcp")
        XCTAssertEqual(request.content, "20 5060 sip.example.com.")
        XCTAssertEqual(request.priority, 10)

        let a = try JSONDecoder().decode(
            DNSimpleZoneRecord.self,
            from: Data(Self.recordJSON(id: 11, type: "A", name: "www", content: "192.0.2.1", priority: nil).utf8)
        )
        let update = try UpdateProviderRecordRequest(content: "192.0.2.2", priority: 50)
            .toDNSimpleRequest(zoneName: "example.com", existing: a)
        XCTAssertNil(update.priority)
    }

    func testSecondaryZonesAndManagedRecordsRejectMutationsBeforeNetwork() async throws {
        let transport = DNSimpleRecordingTransport { _, _ in
            XCTFail("Managed data should be rejected before a request")
            throw URLError(.badServerResponse)
        }
        let adapter = DNSimpleDNSProviderService(service: makeService(transport: transport))
        let secondary = DNSimpleZone(
            id: 1,
            accountId: 1010,
            name: "secondary.example",
            reverse: false,
            secondary: true,
            lastTransferredAt: nil,
            active: true,
            createdAt: "2026-07-10T00:00:00Z",
            updatedAt: "2026-07-10T00:00:00Z"
        )
        let zone = ProviderZone(
            provider: .dnsimple,
            snapshot: secondary.snapshot(nameservers: DNSimpleService.nameservers),
            environmentId: UUID()
        )

        do {
            try await adapter.createRecord(
                in: zone,
                payload: CreateProviderRecordRequest(
                    name: "www",
                    type: "A",
                    content: "192.0.2.1",
                    ttl: 300,
                    proxied: nil,
                    priority: nil,
                    comment: nil
                )
            )
            XCTFail("Expected read-only zone error")
        } catch let ProviderOperationError.readOnlyZone(provider, zoneName) {
            XCTAssertEqual(provider, .dnsimple)
            XCTAssertEqual(zoneName, "secondary.example")
        }

        let primary = DNSimpleZone(
            id: 2,
            accountId: 1010,
            name: "primary.example",
            reverse: false,
            secondary: false,
            lastTransferredAt: nil,
            active: true,
            createdAt: "2026-07-10T00:00:00Z",
            updatedAt: "2026-07-10T00:00:00Z"
        )
        let primaryZone = ProviderZone(
            provider: .dnsimple,
            snapshot: primary.snapshot(nameservers: DNSimpleService.nameservers),
            environmentId: UUID()
        )
        let systemRecord = DNSimpleZoneRecord(
            id: 99,
            zoneId: "primary.example",
            parentId: nil,
            name: "",
            content: "ns1.dnsimple.com",
            ttl: 3600,
            priority: nil,
            type: "NS",
            regions: ["global"],
            systemRecord: true,
            createdAt: "2026-07-10T00:00:00Z",
            updatedAt: "2026-07-10T00:00:00Z"
        )
        let record = ProviderRecord(provider: .dnsimple, snapshot: systemRecord.snapshot())

        do {
            try await adapter.deleteRecord(in: primaryZone, record: record)
            XCTFail("Expected read-only record error")
        } catch let ProviderOperationError.readOnlyRecord(provider, recordId) {
            XCTAssertEqual(provider, .dnsimple)
            XCTAssertEqual(recordId, "99")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testValidationErrorObjectIncludesFieldDetails() async throws {
        let transport = DNSimpleRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 400,
                body: #"{"message":"Validation failed","errors":{"content":["can't be blank"],"ttl":["is not a number"]}}"#
            )
        }

        do {
            _ = try await makeService(transport: transport).listZones()
            XCTFail("Expected API error")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .dnsimple)
            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(message, "Validation failed\ncontent: can't be blank\nttl: is not a number")
        }
    }

    func testNumericAccountIdIsRequiredBeforeNetwork() async throws {
        let transport = DNSimpleRecordingTransport { _, _ in
            XCTFail("Invalid credentials should be rejected before a request")
            throw URLError(.badServerResponse)
        }
        let service = try DNSimpleService(
            accountIdProvider: { "not-a-number" },
            tokenProvider: { "token" },
            baseURL: XCTUnwrap(URL(string: "https://api.dnsimple.test/v2")),
            transport: transport,
            sleep: { _ in }
        )

        do {
            _ = try await service.listZones()
            XCTFail("Expected invalid account ID error")
        } catch let ProviderAPIError.missingCredential(provider, field) {
            XCTAssertEqual(provider, .dnsimple)
            XCTAssertEqual(field, "numeric account ID")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func makeService(transport: DNSimpleRecordingTransport) -> DNSimpleService {
        DNSimpleService(
            accountIdProvider: { "1010" },
            tokenProvider: { "dnsimple-token" },
            baseURL: URL(string: "https://api.dnsimple.test/v2")!,
            transport: transport,
            sleep: { _ in }
        )
    }

    private static func zoneJSON(id: Int, name: String) -> String {
        "{\"id\":\(id),\"account_id\":1010,\"name\":\"\(name)\",\"reverse\":false,\"secondary\":false,\"last_transferred_at\":null,\"active\":true,\"created_at\":\"2026-07-10T00:00:00Z\",\"updated_at\":\"2026-07-10T00:00:00Z\"}"
    }

    private static func recordJSON(
        id: Int,
        type: String,
        name: String,
        content: String,
        priority: Int?
    ) -> String {
        let priorityJSON = priority.map(String.init) ?? "null"
        return "{\"id\":\(id),\"zone_id\":\"example.com\",\"parent_id\":null,\"name\":\"\(name)\",\"content\":\"\(content)\",\"ttl\":600,\"priority\":\(priorityJSON),\"type\":\"\(type)\",\"regions\":[\"global\"],\"system_record\":false,\"created_at\":\"2026-07-10T00:00:00Z\",\"updated_at\":\"2026-07-10T00:00:00Z\"}"
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String
    ) throws -> (Data, URLResponse) {
        try (
            Data(body.utf8),
            XCTUnwrap(
                HTTPURLResponse(
                    url: XCTUnwrap(request.url),
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )
            )
        )
    }
}

@MainActor
private final class DNSimpleRecordingTransport: NetworkTransport {
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
