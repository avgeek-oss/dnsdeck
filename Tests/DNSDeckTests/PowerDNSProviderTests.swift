import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class PowerDNSProviderTests: XCTestCase {
    func testListZonesNormalizesEndpointAndUsesAPIKey() async throws {
        let transport = PowerDNSRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://pdns.test/api/v1/servers/localhost/zones")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "pdns-secret")
            return try Self.response(
                request: request,
                status: 200,
                body: #"[{"id":"example.org.","name":"example.org.","kind":"Native"}]"#
            )
        }

        let zones = try await makeService(transport: transport).listZones()

        XCTAssertEqual(zones.map(\.id), ["example.org."])
        XCTAssertEqual(zones[0].snapshot().name, "example.org")
    }

    func testCustomServerAndExistingAPIBaseArePreserved() async throws {
        let transport = PowerDNSRecordingTransport { request, _ in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://pdns.test/prefix/api/v1/servers/authoritative-1/zones"
            )
            return try Self.response(request: request, status: 200, body: "[]")
        }
        let service = makeService(
            endpoint: "https://pdns.test/prefix/api/v1/",
            serverId: "authoritative-1",
            transport: transport
        )

        _ = try await service.listZones()
    }

    func testRemotePlainHTTPIsRejectedBeforeNetwork() async throws {
        let transport = PowerDNSRecordingTransport { _, _ in
            XCTFail("An insecure remote endpoint must not reach the transport")
            throw URLError(.badURL)
        }
        let service = makeService(endpoint: "http://pdns.example.com:8081", transport: transport)

        do {
            _ = try await service.listZones()
            XCTFail("Expected endpoint rejection")
        } catch let ProviderAPIError.invalidURL(provider) {
            XCTAssertEqual(provider, .powerDNS)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testLoopbackHTTPIsAllowed() async throws {
        let transport = PowerDNSRecordingTransport { request, _ in
            XCTAssertEqual(
                request.url?.absoluteString,
                "http://127.0.0.1:8081/api/v1/servers/localhost/zones"
            )
            return try Self.response(request: request, status: 200, body: "[]")
        }

        _ = try await makeService(endpoint: "http://127.0.0.1:8081", transport: transport).listZones()
    }

    func testCreateZoneUsesNativeKindAndOptionalNameserver() async throws {
        let transport = PowerDNSRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONDecoder().decode(
                PowerDNSCreateZoneRequest.self,
                from: XCTUnwrap(request.httpBody)
            )
            XCTAssertEqual(
                body,
                PowerDNSCreateZoneRequest(
                    name: "example.org.",
                    kind: "Native",
                    masters: [],
                    nameservers: ["ns1.example.org."]
                )
            )
            return try Self.response(
                request: request,
                status: 201,
                body: #"{"id":"example.org.","name":"example.org.","kind":"Native","rrsets":[]}"#
            )
        }

        let zone = try await makeService(nameserver: "ns1.example.org", transport: transport)
            .createZone(name: "example.org")

        XCTAssertEqual(zone.name, "example.org.")
    }

    func testGetZoneRequestsRRsetsAndDisabledRecords() async throws {
        let transport = PowerDNSRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/localhost/zones/example.org.")
            XCTAssertEqual(request.url?.query, "rrsets=true&include_disabled=true")
            return try Self.response(
                request: request,
                status: 200,
                body: Self.zoneFixture
            )
        }

        let zone = try await makeService(transport: transport).getZone(id: "example.org.")

        XCTAssertEqual(zone.snapshot().nameservers, ["ns1.example.org."])
        XCTAssertEqual(zone.rrsets?.count, 2)
    }

    func testPatchEncodesFullRRsetAndDeleteChange() async throws {
        let replace = PowerDNSRRsetChange(
            name: "www.example.org.",
            type: "A",
            ttl: 3600,
            changetype: "REPLACE",
            records: [PowerDNSRecordWrite(content: "192.0.2.1", disabled: false)],
            comments: [PowerDNSCommentWrite(content: "web", account: "dnsdeck")]
        )
        let transport = PowerDNSRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/servers/localhost/zones/example.org.")
            XCTAssertEqual(
                try JSONDecoder().decode(PowerDNSZonePatch.self, from: XCTUnwrap(request.httpBody)),
                PowerDNSZonePatch(
                    rrsets: [replace, .delete(name: "old.example.org.", type: "A")]
                )
            )
            return try Self.response(request: request, status: 204, body: "")
        }

        try await makeService(transport: transport).patchZone(
            id: "example.org.",
            changes: [replace, .delete(name: "old.example.org.", type: "A")]
        )
    }

    func testUpdatePreservesDisabledRecordsAndCommentsWithoutValueEdits() throws {
        let existing = PowerDNSRRset(
            name: "www.example.org.",
            type: "TXT",
            ttl: 3600,
            records: [
                PowerDNSRecord(content: #""active""#, disabled: false),
                PowerDNSRecord(content: #""paused""#, disabled: true),
            ],
            comments: [PowerDNSComment(content: "managed", account: "ops", modifiedAt: 123)]
        )

        let change = try UpdateProviderRecordRequest(ttl: 7200)
            .toPowerDNSChange(zoneName: "example.org.", existing: existing)

        XCTAssertEqual(change.records?[0], PowerDNSRecordWrite(content: #""active""#, disabled: false))
        XCTAssertEqual(change.records?[1], PowerDNSRecordWrite(content: #""paused""#, disabled: true))
        XCTAssertEqual(change.comments, [PowerDNSCommentWrite(content: "managed", account: "ops")])
        XCTAssertEqual(change.ttl, 7200)
    }

    func testSnapshotRetainsNativeStateAndNormalizesDisplay() throws {
        let zone = try JSONDecoder().decode(PowerDNSZone.self, from: Data(Self.zoneFixture.utf8))
        let txt = try XCTUnwrap(zone.rrsets?.last?.snapshot(zoneName: zone.name))

        XCTAssertEqual(txt.name, "www")
        XCTAssertEqual(txt.values, ["active", "paused"])
        XCTAssertEqual(txt.metadata["disabledCount"], "1")
        XCTAssertEqual(txt.comment, "managed")
        XCTAssertNotNil(txt.providerData)
    }

    func testSecondaryZoneIsReadOnlyBeforeNetwork() async throws {
        let transport = PowerDNSRecordingTransport { _, _ in
            XCTFail("A secondary zone mutation must not reach the transport")
            throw URLError(.badServerResponse)
        }
        let adapter = PowerDNSDNSProviderService(service: makeService(transport: transport))
        let secondary = try JSONDecoder().decode(
            PowerDNSZone.self,
            from: Data(#"{"id":"secondary.example.","name":"secondary.example.","kind":"Slave"}"#.utf8)
        )
        let zone = ProviderZone(provider: .powerDNS, snapshot: secondary.snapshot(), environmentId: UUID())

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
        } catch let ProviderOperationError.readOnlyZone(provider, _) {
            XCTAssertEqual(provider, .powerDNS)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testPowerDNSErrorIncludesAllValidationMessages() async throws {
        let transport = PowerDNSRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 422,
                body: #"{"error":"Record validation failed","errors":["invalid A content","name is outside zone"]}"#
            )
        }

        do {
            _ = try await makeService(transport: transport).listZones()
            XCTFail("Expected API error")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .powerDNS)
            XCTAssertEqual(statusCode, 422)
            XCTAssertEqual(message, "Record validation failed\ninvalid A content\nname is outside zone")
        }
    }

    private func makeService(
        endpoint: String = "https://pdns.test",
        serverId: String? = nil,
        nameserver: String? = nil,
        transport: PowerDNSRecordingTransport
    ) -> PowerDNSService {
        PowerDNSService(
            credentialsProvider: {
                (endpoint: endpoint, apiKey: "pdns-secret", serverId: serverId, nameserver: nameserver)
            },
            transport: transport,
            sleep: { _ in }
        )
    }

    private static let zoneFixture = #"{"id":"example.org.","name":"example.org.","kind":"Native","dnssec":true,"rrsets":[{"name":"example.org.","type":"NS","ttl":3600,"records":[{"content":"ns1.example.org.","disabled":false}],"comments":[]},{"name":"www.example.org.","type":"TXT","ttl":3600,"records":[{"content":"\"active\"","disabled":false},{"content":"\"paused\"","disabled":true}],"comments":[{"content":"managed","account":"ops","modified_at":123}]}]}"#

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
private final class PowerDNSRecordingTransport: NetworkTransport {
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
