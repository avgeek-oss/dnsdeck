import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class UltraDNSProviderTests: XCTestCase {
    func testTokenAndCursorZonePagination() async throws {
        let transport = UltraDNSRecordingTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/authorization/token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
                XCTAssertEqual(
                    try String(data: XCTUnwrap(request.httpBody), encoding: .utf8),
                    "grant_type=password&username=user%40example.com&password=p%26ss"
                )
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"access_token":"access","expires_in":"3600"}"#
                )
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            XCTAssertEqual(request.url?.path, "/v3/zones")
            let page = index - 1
            XCTAssertEqual(request.url?.query, page == 0 ? "limit=1000" : "limit=1000&cursor=next-token")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"cursorInfo":\#(page == 0 ? "{\"next\":\"next-token\"}" : "{}"),"zones":[\#(Self.zoneFixture(name: page == 0 ? "one.example." : "two.example."))]}"#
            )
        }

        let zones = try await makeService(transport: transport).listZones()

        XCTAssertEqual(zones.map(\.name), ["one.example", "two.example"])
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testReverseZoneSlashIsEncodedAsOnePathSegment() async throws {
        let transport = UltraDNSRecordingTransport { request, index in
            if index == 0 { return try Self.tokenResponse(request) }
            XCTAssertEqual(
                request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath },
                "/zones/0%2F24.50.156.193.in-addr.arpa"
            )
            return try Self.response(
                request: request,
                status: 200,
                body: Self.zoneFixture(name: "0/24.50.156.193.in-addr.arpa.")
            )
        }

        _ = try await makeService(transport: transport).getZone(name: "0/24.50.156.193.in-addr.arpa")
    }

    func testRRSetOffsetPaginationAndSystemGeneratedStatus() async throws {
        let transport = UltraDNSRecordingTransport { request, index in
            if index == 0 { return try Self.tokenResponse(request) }
            let page = index - 1
            XCTAssertEqual(request.url?.path, "/zones/example.com/rrsets")
            XCTAssertEqual(
                request.url?.query,
                "offset=\(page)&limit=1000&systemGeneratedStatus=true"
            )
            let rrset = page == 0
                ? #"{"ownerName":"www.example.com.","rrtype":"A (1)","ttl":300,"rdata":["192.0.2.1"],"systemGenerated":[false]}"#
                : #"{"ownerName":"example.com.","rrtype":"NS (2)","ttl":86400,"rdata":["udns1.ultradns.net."],"systemGenerated":[true]}"#
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"zoneName":"example.com.","rrSets":[\#(rrset)],"resultInfo":{"totalCount":2,"offset":\#(page),"returnedCount":1}}"#
            )
        }

        let records = try await makeService(transport: transport).listRRSets(zoneName: "example.com")

        XCTAssertEqual(records.count, 2)
        XCTAssertFalse(records[0].isProtected)
        XCTAssertTrue(records[1].isProtected)
    }

    func testRRSetCreateReplaceDeleteMethodsUseCompleteSetBodies() async throws {
        let write = UltraDNSRRSetWrite(ttl: 300, rdata: ["192.0.2.1", "192.0.2.2"])
        let transport = UltraDNSRecordingTransport { request, index in
            if index == 0 { return try Self.tokenResponse(request) }
            XCTAssertEqual(request.url?.path, "/zones/example.com/rrsets/A/www.example.com.")
            XCTAssertEqual(request.httpMethod, ["POST", "PUT", "DELETE"][index - 1])
            if index < 3 {
                XCTAssertEqual(
                    try JSONDecoder().decode(UltraDNSRRSetWrite.self, from: XCTUnwrap(request.httpBody)),
                    write
                )
            }
            return try Self.response(request: request, status: index == 1 ? 201 : 200, body: "{}")
        }
        let service = makeService(transport: transport)

        try await service.createRRSet(zone: "example.com", owner: "www.example.com.", type: "A", write: write)
        try await service.replaceRRSet(zone: "example.com", owner: "www.example.com.", type: "A", write: write)
        try await service.deleteRRSet(zone: "example.com", owner: "www.example.com.", type: "A")
    }

    func testMappingPreservesCompleteMXSetAndApexAlias() throws {
        let mx = try CreateProviderRecordRequest(
            name: "@",
            type: "MX",
            content: "mail1.example.com.",
            ttl: 600,
            proxied: nil,
            priority: 10,
            comment: nil,
            values: ["mail1.example.com.", "20 mail2.example.com."]
        ).toUltraDNSRRSet(zoneName: "example.com")
        XCTAssertEqual(mx.owner, "example.com.")
        XCTAssertEqual(mx.write.rdata, ["10 mail1.example.com.", "20 mail2.example.com."])

        let alias = try CreateProviderRecordRequest(
            name: "",
            type: "APEXALIAS",
            content: "",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil,
            aliasTarget: "target.example.net."
        ).toUltraDNSRRSet(zoneName: "example.com")
        XCTAssertEqual(alias.owner, "example.com.")
        XCTAssertEqual(alias.write.rdata, ["target.example.net."])
    }

    func testMXUpdatePreservesEachExistingPriorityUnlessOverridden() throws {
        let existing = UltraDNSRRSet(
            ownerName: "example.com.",
            rrtype: "MX (15)",
            ttl: 600,
            rdata: ["20 mail1.example.com.", "30 mail2.example.com."],
            profile: nil,
            systemGenerated: nil,
            ultra2SystemGenerated: nil
        )

        let preserved = try UpdateProviderRecordRequest(
            values: ["new1.example.com.", "new2.example.com."]
        ).toUltraDNSRRSet(zoneName: "example.com", existing: existing)
        XCTAssertEqual(preserved.write.rdata, ["20 new1.example.com.", "30 new2.example.com."])

        let overridden = try UpdateProviderRecordRequest(
            priority: 40,
            values: ["new1.example.com.", "new2.example.com."]
        ).toUltraDNSRRSet(zoneName: "example.com", existing: existing)
        XCTAssertEqual(overridden.write.rdata, ["40 new1.example.com.", "40 new2.example.com."])
    }

    func testTypeChangeRequiresReplacementValues() throws {
        let existing = UltraDNSRRSet(
            ownerName: "www.example.com.",
            rrtype: "A (1)",
            ttl: 300,
            rdata: ["192.0.2.1"],
            profile: nil,
            systemGenerated: nil,
            ultra2SystemGenerated: nil
        )

        XCTAssertThrowsError(
            try UpdateProviderRecordRequest(type: "AAAA")
                .toUltraDNSRRSet(zoneName: "example.com", existing: existing)
        )
    }

    func testSecondaryZoneAndPoolRecordAreReadOnlyBeforeNetwork() async throws {
        let transport = UltraDNSRecordingTransport { _, _ in
            XCTFail("Read-only mutations must not reach the network")
            throw URLError(.badServerResponse)
        }
        let adapter = UltraDNSProviderService(service: makeService(transport: transport))
        let secondary = try JSONDecoder().decode(
            UltraDNSZone.self,
            from: Data(Self.zoneFixture(name: "example.com.", type: "SECONDARY").utf8)
        )
        let zone = ProviderZone(provider: .ultraDNS, snapshot: secondary.snapshot(), environmentId: UUID())

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
            XCTAssertEqual(provider, .ultraDNS)
        }
        XCTAssertTrue(transport.requests.isEmpty)

        let pool = UltraDNSRRSet(
            ownerName: "www.example.com.",
            rrtype: "A (1)",
            ttl: 300,
            rdata: ["192.0.2.1"],
            profile: .object(["@context": .string("http://schemas.ultradns.com/RDPool.jsonschema")]),
            systemGenerated: nil,
            ultra2SystemGenerated: nil
        )
        XCTAssertTrue(ProviderRecord(provider: .ultraDNS, snapshot: pool.snapshot(zoneName: "example.com"))
            .isEditable == false)
    }

    private func makeService(transport: UltraDNSRecordingTransport) -> UltraDNSService {
        UltraDNSService(
            credentialsProvider: { (username: "user@example.com", password: "p&ss") },
            baseURL: URL(string: "https://ultra.test")!,
            transport: transport,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1000) }
        )
    }

    private static func zoneFixture(name: String, type: String = "PRIMARY") -> String {
        #"{"properties":{"name":"\#(name)","accountName":"account","owner":"owner","type":"\#(type)","dnssecStatus":"UNSIGNED","status":"ACTIVE","resourceRecordCount":2,"lastModifiedDateTime":"2026-07-10T12:00Z","ultra2":false},"registrarInfo":{"nameServers":{"ok":["udns1.ultradns.net."],"unknown":[],"missing":["udns2.ultradns.net."],"incorrect":[]}},"originalZoneName":null}"#
    }

    private static func tokenResponse(_ request: URLRequest) throws -> (Data, URLResponse) {
        try response(request: request, status: 200, body: #"{"access_token":"access","expires_in":3600}"#)
    }

    private static func response(request: URLRequest, status: Int, body: String) throws -> (Data, URLResponse) {
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
private final class UltraDNSRecordingTransport: NetworkTransport {
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
