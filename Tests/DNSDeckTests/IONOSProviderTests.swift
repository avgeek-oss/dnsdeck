import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class IONOSProviderTests: XCTestCase {
    func testListZonesUsesHostingAPIKeyAndPreservesZoneType() async throws {
        let transport = IONOSRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/dns/v1/zones")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "prefix.secret")
            return try Self.response(
                request: request,
                status: 200,
                body: #"[{"id":"zone-1","name":"example.com","type":"NATIVE"},{"id":"zone-2","name":"secondary.example","type":"SLAVE"}]"#
            )
        }

        let zones = try await makeService(transport: transport).listZones()

        XCTAssertEqual(zones.map(\.id), ["zone-1", "zone-2"])
        XCTAssertEqual(zones[1].snapshot().status, "SLAVE")
        XCTAssertNotNil(zones[1].snapshot().providerData)
    }

    func testZoneDetailsExtractsOnlyActiveApexNameservers() async throws {
        let transport = IONOSRecordingTransport { request, _ in
            XCTAssertEqual(request.url?.path, "/dns/v1/zones/zone-1")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"id":"zone-1","name":"example.com","type":"NATIVE","records":[{"id":"ns-1","name":"example.com","rootName":"example.com","type":"NS","content":"ns1.ui-dns.com.","ttl":3600,"prio":0,"disabled":false},{"id":"ns-2","name":"child.example.com","rootName":"example.com","type":"NS","content":"ns.child.example.","ttl":3600,"prio":0,"disabled":false},{"id":"ns-3","name":"example.com","rootName":"example.com","type":"NS","content":"disabled.example.","ttl":3600,"prio":0,"disabled":true}]}"#
            )
        }
        let adapter = IONOSDNSProviderService(service: makeService(transport: transport))

        let zone = try await adapter.zoneDetails(for: providerZone())

        XCTAssertEqual(zone.nameservers, ["ns1.ui-dns.com."])
    }

    func testRecordSnapshotUnquotesTXTAndPreservesNativeState() {
        let record = IONOSRecord(
            id: "record-1",
            name: "_acme-challenge.example.com",
            rootName: "example.com",
            type: "TXT",
            content: #""first\"part" "second""#,
            changeDate: "2026-07-10T12:30:00.000Z",
            ttl: 300,
            prio: 0,
            disabled: true
        )

        let snapshot = record.snapshot()

        XCTAssertEqual(snapshot.values, [#"first"partsecond"#])
        XCTAssertEqual(snapshot.metadata["disabled"], "true")
        XCTAssertNotNil(snapshot.modifiedOn)
        XCTAssertNotNil(snapshot.providerData)
    }

    func testGetRecordUsesRecordIDEndpoint() async throws {
        let transport = IONOSRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/dns/v1/zones/zone-1/records/record-1")
            return try Self.response(
                request: request,
                status: 200,
                body: Self.recordJSON(id: "record-1")
            )
        }

        let record = try await makeService(transport: transport).getRecord(
            zoneId: "zone-1",
            recordId: "record-1"
        )

        XCTAssertEqual(record.id, "record-1")
        XCTAssertEqual(record.name, "www.example.com")
    }

    func testRecordCRUDUsesDocumentedArrayCreateAndPartialUpdate() async throws {
        let create = IONOSRecordCreateRequest(
            name: "www.example.com",
            type: "A",
            content: "192.0.2.1",
            ttl: 3600,
            prio: nil,
            disabled: false
        )
        let update = IONOSRecordUpdateRequest(
            content: "192.0.2.2",
            ttl: 600,
            prio: nil,
            disabled: false
        )
        let transport = IONOSRecordingTransport { request, index in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "prefix.secret")
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/dns/v1/zones/zone-1/records")
                XCTAssertEqual(
                    try JSONDecoder().decode([IONOSRecordCreateRequest].self, from: XCTUnwrap(request.httpBody)),
                    [create]
                )
                return try Self.response(
                    request: request,
                    status: 201,
                    body: Self.recordJSON(id: "record-1", content: create.content, ttl: create.ttl)
                        .wrappedInArray
                )
            }
            if index == 1 {
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path, "/dns/v1/zones/zone-1/records/record-1")
                XCTAssertEqual(
                    try JSONDecoder().decode(IONOSRecordUpdateRequest.self, from: XCTUnwrap(request.httpBody)),
                    update
                )
                return try Self.response(
                    request: request,
                    status: 200,
                    body: Self.recordJSON(id: "record-1", content: update.content, ttl: update.ttl)
                )
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/dns/v1/zones/zone-1/records/record-1")
            return try Self.response(request: request, status: 200, body: "")
        }
        let service = makeService(transport: transport)

        _ = try await service.createRecords(zoneId: "zone-1", requests: [create])
        _ = try await service.updateRecord(zoneId: "zone-1", recordId: "record-1", request: update)
        try await service.deleteRecord(zoneId: "zone-1", recordId: "record-1")

        XCTAssertEqual(transport.requests.count, 3)
    }

    func testMappingsUseAbsoluteNamesTTLFloorAndNativePriorities() throws {
        let mx = try CreateProviderRecordRequest(
            name: "@",
            type: "MX",
            content: "20 mail.example.com.",
            ttl: 60,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toIONOSMutations(zoneName: "example.com")
        XCTAssertEqual(mx[0].name, "example.com")
        XCTAssertEqual(mx[0].content, "mail.example.com.")
        XCTAssertEqual(mx[0].priority, 20)
        XCTAssertEqual(mx[0].ttl, 300)

        let srv = try CreateProviderRecordRequest(
            name: "_sip._tcp",
            type: "SRV",
            content: "10 5 443 sip.example.com.",
            ttl: 3600,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toIONOSMutations(zoneName: "example.com")
        XCTAssertEqual(srv[0].name, "_sip._tcp.example.com")
        XCTAssertEqual(srv[0].content, "5 443 sip.example.com.")
        XCTAssertEqual(srv[0].priority, 10)

        let txt = try CreateProviderRecordRequest(
            name: "verify",
            type: "TXT",
            content: #""quoted value""#,
            ttl: 3600,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toIONOSMutations(zoneName: "example.com")
        XCTAssertEqual(txt[0].content, "quoted value")
    }

    func testAdapterCreatesMultipleValuesInOneBatch() async throws {
        let transport = IONOSRecordingTransport { request, _ in
            let body = try JSONDecoder().decode(
                [IONOSRecordCreateRequest].self,
                from: XCTUnwrap(request.httpBody)
            )
            XCTAssertEqual(body.map(\.content), ["192.0.2.1", "192.0.2.2"])
            return try Self.response(
                request: request,
                status: 201,
                body: "[\(Self.recordJSON(id: "record-1", content: body[0].content, ttl: body[0].ttl)),\(Self.recordJSON(id: "record-2", content: body[1].content, ttl: body[1].ttl))]"
            )
        }
        let adapter = IONOSDNSProviderService(service: makeService(transport: transport))

        try await adapter.createRecord(
            in: providerZone(),
            payload: CreateProviderRecordRequest(
                name: "www",
                type: "A",
                content: "192.0.2.1",
                ttl: 3600,
                proxied: nil,
                priority: nil,
                comment: nil,
                values: ["192.0.2.1", "192.0.2.2"]
            )
        )

        XCTAssertEqual(transport.requests.count, 1)
    }

    func testRenameRollsBackCreatedRecordWhenSourceDeleteFails() async throws {
        let transport = IONOSRecordingTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "POST")
                return try Self.response(
                    request: request,
                    status: 201,
                    body: Self.recordJSON(id: "new-record", name: "renamed.example.com").wrappedInArray
                )
            }
            if index == 1 {
                XCTAssertEqual(request.url?.path, "/dns/v1/zones/zone-1/records/old-record")
                return try Self.response(
                    request: request,
                    status: 500,
                    body: #"[{"code":"INTERNAL_SERVER_ERROR","message":"source delete failed"}]"#
                )
            }
            XCTAssertEqual(request.url?.path, "/dns/v1/zones/zone-1/records/new-record")
            return try Self.response(request: request, status: 200, body: "")
        }
        let adapter = IONOSDNSProviderService(service: makeService(transport: transport))

        do {
            try await adapter.updateRecord(
                in: providerZone(),
                record: providerRecord(id: "old-record"),
                edits: UpdateProviderRecordRequest(name: "renamed")
            )
            XCTFail("Expected source delete failure")
        } catch let ProviderAPIError.http(_, statusCode, message, _, _) {
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(message, "INTERNAL_SERVER_ERROR: source delete failed")
        }
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testSlaveZoneIsReadOnlyWithoutSendingARequest() async throws {
        let transport = IONOSRecordingTransport { request, _ in
            XCTFail("Unexpected request: \(request)")
            throw URLError(.badServerResponse)
        }
        let adapter = IONOSDNSProviderService(service: makeService(transport: transport))

        do {
            try await adapter.createRecord(
                in: providerZone(type: "SLAVE"),
                payload: CreateProviderRecordRequest(
                    name: "www",
                    type: "A",
                    content: "192.0.2.1",
                    ttl: 3600,
                    proxied: nil,
                    priority: nil,
                    comment: nil
                )
            )
            XCTFail("Expected read-only zone error")
        } catch ProviderOperationError.readOnlyZone(.ionos, "example.com") {}
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testArrayErrorEnvelopeRetainsCodeAndMessage() async throws {
        let transport = IONOSRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 401,
                body: #"[{"code":"UNAUTHORIZED","message":"The customer is not authorized."}]"#
            )
        }

        do {
            _ = try await makeService(transport: transport).listZones()
            XCTFail("Expected authorization error")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .ionos)
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "UNAUTHORIZED: The customer is not authorized.")
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    private func makeService(transport: IONOSRecordingTransport) -> IONOSService {
        IONOSService(
            apiKeyProvider: { "prefix.secret" },
            baseURL: URL(string: "https://api.ionos.test/dns")!,
            transport: transport,
            sleep: { _ in }
        )
    }

    private func providerZone(type: String = "NATIVE") -> ProviderZone {
        ProviderZone(
            provider: .ionos,
            snapshot: IONOSZone(id: "zone-1", name: "example.com", type: type).snapshot(),
            environmentId: UUID()
        )
    }

    private func providerRecord(id: String) -> ProviderRecord {
        ProviderRecord(
            provider: .ionos,
            snapshot: IONOSRecord(
                id: id,
                name: "www.example.com",
                rootName: "example.com",
                type: "A",
                content: "192.0.2.1",
                changeDate: nil,
                ttl: 3600,
                prio: 0,
                disabled: false
            ).snapshot()
        )
    }

    private static func recordJSON(
        id: String,
        name: String = "www.example.com",
        content: String = "192.0.2.1",
        ttl: Int = 3600
    ) -> String {
        "{\"id\":\"\(id)\",\"name\":\"\(name)\",\"rootName\":\"example.com\",\"type\":\"A\",\"content\":\"\(content)\",\"changeDate\":\"2026-07-10T12:30:00.000Z\",\"ttl\":\(ttl),\"prio\":0,\"disabled\":false}"
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

private extension String {
    var wrappedInArray: String {
        "[\(self)]"
    }
}

@MainActor
private final class IONOSRecordingTransport: NetworkTransport {
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
