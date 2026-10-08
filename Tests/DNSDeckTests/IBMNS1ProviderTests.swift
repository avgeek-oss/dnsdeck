import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class IBMNS1ProviderTests: XCTestCase {
    func testZonePaginationUsesAPIKeyAndTrustedNextLink() async throws {
        let transport = IBMNS1RecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-NSONE-Key"), "ns1-secret")
            XCTAssertEqual(request.url?.path, "/v1/zones")
            XCTAssertEqual(request.url?.query, index == 0 ? nil : "page=2")
            return try Self.response(
                request: request,
                status: 200,
                body: "[\(Self.zoneFixture(name: index == 0 ? "one.example" : "two.example"))]",
                headers: index == 0
                    ? ["Link": #"<https://ns1.test/v1/zones?page=2>; rel="next""#]
                    : [:]
            )
        }

        let zones = try await makeService(transport: transport).listZones()

        XCTAssertEqual(zones.map(\.zone), ["one.example", "two.example"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testUntrustedPaginationLinkIsRejected() async throws {
        let transport = IBMNS1RecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 200,
                body: "[]",
                headers: ["Link": #"<https://attacker.example/zones?page=2>; rel="next""#]
            )
        }

        do {
            _ = try await makeService(transport: transport).listZones()
            XCTFail("Expected an untrusted pagination URL error")
        } catch let ProviderAPIError.untrustedURL(provider, url) {
            XCTAssertEqual(provider, .ibmNS1)
            XCTAssertEqual(url.host, "attacker.example")
        }
    }

    func testZoneDetailsCombinesPaginatedRecordSummaries() async throws {
        let transport = IBMNS1RecordingTransport { request, index in
            XCTAssertEqual(request.url?.path, "/v1/zones/example.com")
            let summary = index == 0
                ? #"{"domain":"www.example.com","id":"a","link":null,"short_answers":["192.0.2.1"],"ttl":300,"type":"A"}"#
                : #"{"domain":"mail.example.com","id":"mx","link":null,"short_answers":["10 mx.example.com"],"ttl":600,"type":"MX"}"#
            return try Self.response(
                request: request,
                status: 200,
                body: Self.zoneFixture(name: "example.com", records: "[\(summary)]"),
                headers: index == 0
                    ? ["Link": #"<https://ns1.test/v1/zones/example.com?page=2>; rel="next""#]
                    : [:]
            )
        }

        let zone = try await makeService(transport: transport).getZone(name: "example.com")

        XCTAssertEqual(zone.records?.map(\.id), ["a", "mx"])
    }

    func testListRecordsFetchesCompleteRecordConfiguration() async throws {
        let transport = IBMNS1RecordingTransport { request, index in
            if index == 0 {
                return try Self.response(
                    request: request,
                    status: 200,
                    body: Self.zoneFixture(
                        name: "example.com",
                        records: #"[{"domain":"www.example.com","id":"a","link":null,"short_answers":["192.0.2.1"],"ttl":300,"type":"A"}]"#
                    )
                )
            }
            XCTAssertEqual(request.url?.path, "/v1/zones/example.com/www.example.com/A")
            return try Self.response(request: request, status: 200, body: Self.recordFixture())
        }

        let records = try await makeService(transport: transport).listRecords(zoneName: "example.com")

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].answers[0].answer, [.string("192.0.2.1")])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testLegacyCreateUpdateDeleteMethodsAndBodies() async throws {
        let record = try JSONDecoder().decode(IBMNS1Record.self, from: Data(Self.recordFixture().utf8))
        let transport = IBMNS1RecordingTransport { request, index in
            XCTAssertEqual(request.url?.path, "/v1/zones/example.com/www.example.com/A")
            XCTAssertEqual(request.httpMethod, ["PUT", "POST", "DELETE"][index])
            if index < 2 {
                XCTAssertEqual(
                    try JSONDecoder().decode(IBMNS1RecordMutation.self, from: XCTUnwrap(request.httpBody)),
                    record.mutation()
                )
                let object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
                )
                XCTAssertNil(object["id"])
                XCTAssertNil(object["link"])
                XCTAssertNil(object["tags"])
                XCTAssertNil(object["blocked_tags"])
            }
            return try Self.response(request: request, status: 200, body: "{}")
        }
        let service = makeService(transport: transport)

        try await service.createRecord(record)
        try await service.updateRecord(record)
        try await service.deleteRecord(zone: record.zone, domain: record.domain, type: record.type)
    }

    func testZoneCreateAndDeleteUseLegacyPUTAndDELETE() async throws {
        let transport = IBMNS1RecordingTransport { request, index in
            XCTAssertEqual(request.url?.path, "/v1/zones/example.com")
            XCTAssertEqual(request.httpMethod, index == 0 ? "PUT" : "DELETE")
            if index == 0 {
                XCTAssertEqual(
                    try JSONDecoder().decode(IBMNS1CreateZoneRequest.self, from: XCTUnwrap(request.httpBody)),
                    IBMNS1CreateZoneRequest(zone: "example.com")
                )
                return try Self.response(request: request, status: 200, body: Self.zoneFixture(name: "example.com"))
            }
            return try Self.response(request: request, status: 200, body: "{}")
        }
        let service = makeService(transport: transport)

        _ = try await service.createZone(name: "example.com")
        try await service.deleteZone(name: "example.com")
    }

    func testRecordMappingPreservesMultiAnswerMXAndSRVShapes() throws {
        let mx = try CreateProviderRecordRequest(
            name: "@",
            type: "MX",
            content: "mx1.example.com",
            ttl: 300,
            proxied: nil,
            priority: 10,
            comment: nil,
            values: ["mx1.example.com", "20 mx2.example.com"]
        ).toIBMNS1Record(zoneName: "example.com")
        XCTAssertEqual(mx.domain, "example.com")
        XCTAssertEqual(mx.answers[0].answer, [.number(10), .string("mx1.example.com")])
        XCTAssertEqual(mx.answers[1].answer, [.number(20), .string("mx2.example.com")])
        XCTAssertEqual(mx.snapshot().values, ["mx1.example.com", "mx2.example.com"])

        let srv = try CreateProviderRecordRequest(
            name: "_sip._tcp",
            type: "SRV",
            content: "10 5 5060 sip.example.com",
            ttl: 600,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toIBMNS1Record(zoneName: "example.com")
        XCTAssertEqual(
            srv.answers[0].answer,
            [.number(10), .number(5), .number(5060), .string("sip.example.com")]
        )

        let ds = try CreateProviderRecordRequest(
            name: "child",
            type: "DS",
            content: "12345 13 2 ABCDEF",
            ttl: 600,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toIBMNS1Record(zoneName: "example.com")
        XCTAssertEqual(
            ds.answers[0].answer,
            [.string("12345"), .string("13"), .string("2"), .string("ABCDEF")]
        )

        let alias = try CreateProviderRecordRequest(
            name: "",
            type: "ALIAS",
            content: "",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil,
            aliasTarget: "target.example.net"
        ).toIBMNS1Record(zoneName: "example.com")
        XCTAssertEqual(alias.domain, "example.com")
        XCTAssertEqual(alias.answers[0].answer, [.string("target.example.net")])
    }

    func testTTLOnlyEditPreservesAdvancedConfigurationButContentEditIsRejected() throws {
        let existing = try JSONDecoder().decode(
            IBMNS1Record.self,
            from: Data(Self.recordFixture(advanced: true).utf8)
        )

        let ttlOnly = try UpdateProviderRecordRequest(ttl: 600)
            .toIBMNS1Record(zoneName: "example.com", existing: existing)
        XCTAssertEqual(ttlOnly.answers, existing.answers)
        XCTAssertEqual(ttlOnly.filters, existing.filters)
        XCTAssertEqual(ttlOnly.regions, existing.regions)

        XCTAssertThrowsError(
            try UpdateProviderRecordRequest(content: "192.0.2.2")
                .toIBMNS1Record(zoneName: "example.com", existing: existing)
        )
        XCTAssertThrowsError(
            try UpdateProviderRecordRequest(name: "moved")
                .toIBMNS1Record(zoneName: "example.com", existing: existing)
        )
    }

    func testRenamePreservesAllStandardAnswersAndPriorityEditUpdatesEachAnswer() throws {
        let existing = try JSONDecoder().decode(
            IBMNS1Record.self,
            from: Data(
                #"{"id":"record-mx","zone":"example.com","domain":"example.com","type":"MX","link":null,"ttl":300,"answers":[{"id":"answer-a","answer":[10,"mx1.example.com"],"meta":null,"feeds":[],"region":null},{"id":"answer-b","answer":[20,"mx2.example.com"],"meta":null,"feeds":[],"region":null}],"filters":[],"regions":{},"meta":null,"tags":{},"blocked_tags":[],"override_ttl":false,"override_address_records":false,"use_client_subnet":false}"#
                    .utf8
            )
        )

        let renamed = try UpdateProviderRecordRequest(name: "mail")
            .toIBMNS1Record(zoneName: "example.com", existing: existing)
        XCTAssertEqual(renamed.domain, "mail.example.com")
        XCTAssertEqual(renamed.answers, existing.answers)

        let reprioritized = try UpdateProviderRecordRequest(priority: 30)
            .toIBMNS1Record(zoneName: "example.com", existing: existing)
        XCTAssertEqual(reprioritized.answers.count, 2)
        XCTAssertEqual(reprioritized.answers[0].answer, [.number(30), .string("mx1.example.com")])
        XCTAssertEqual(reprioritized.answers[1].answer, [.number(30), .string("mx2.example.com")])
        XCTAssertEqual(reprioritized.answers.map(\.id), ["answer-a", "answer-b"])
    }

    func testTypeChangeRequiresReplacementValues() throws {
        let existing = try JSONDecoder().decode(
            IBMNS1Record.self,
            from: Data(Self.recordFixture().utf8)
        )

        XCTAssertThrowsError(
            try UpdateProviderRecordRequest(type: "AAAA")
                .toIBMNS1Record(zoneName: "example.com", existing: existing)
        )
    }

    func testSecondaryAndLinkedZonesAreReadOnlyBeforeNetwork() async throws {
        for zoneData in [
            IBMNS1Zone(
                id: "secondary",
                zone: "secondary.example",
                dnsServers: [],
                ttl: nil,
                nxTTL: nil,
                serial: nil,
                link: nil,
                networks: nil,
                records: [],
                secondary: IBMNS1Secondary(enabled: true, status: "connected", expired: false),
                dnssec: nil,
                tags: nil
            ),
            IBMNS1Zone(
                id: "linked",
                zone: "linked.example",
                dnsServers: [],
                ttl: nil,
                nxTTL: nil,
                serial: nil,
                link: "source.example",
                networks: nil,
                records: [],
                secondary: nil,
                dnssec: nil,
                tags: nil
            ),
        ] {
            let transport = IBMNS1RecordingTransport { _, _ in
                XCTFail("A read-only zone mutation must not reach the network")
                throw URLError(.badServerResponse)
            }
            let adapter = IBMNS1DNSProviderService(service: makeService(transport: transport))
            let zone = ProviderZone(provider: .ibmNS1, snapshot: zoneData.snapshot(), environmentId: UUID())

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
                XCTFail("Expected a read-only zone error")
            } catch let ProviderOperationError.readOnlyZone(provider, _) {
                XCTAssertEqual(provider, .ibmNS1)
            }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    private func makeService(transport: IBMNS1RecordingTransport) -> IBMNS1Service {
        IBMNS1Service(
            apiKeyProvider: { "ns1-secret" },
            baseURL: URL(string: "https://ns1.test/v1")!,
            transport: transport,
            sleep: { _ in }
        )
    }

    private static func zoneFixture(name: String, records: String = "[]") -> String {
        #"{"id":"zone-\#(name)","zone":"\#(name)","dns_servers":["dns1.p01.nsone.net"],"ttl":3600,"nx_ttl":3600,"serial":1,"link":null,"networks":[0],"records":\#(records),"secondary":{"enabled":false,"status":"","expired":false},"dnssec":false,"tags":{}}"#
    }

    private static func recordFixture(advanced: Bool = false) -> String {
        let filters = advanced ? #"[{"filter":"up"}]"# : "[]"
        let regions = advanced ? #"{"us":{"meta":{"country":["US"]}}}"# : "{}"
        let answerMeta = advanced ? #"{"up":true}"# : "null"
        return #"{"id":"record-a","zone":"example.com","domain":"www.example.com","type":"A","link":null,"ttl":300,"answers":[{"id":"answer-a","answer":["192.0.2.1"],"meta":\#(answerMeta),"feeds":[],"region":null}],"filters":\#(filters),"regions":\#(regions),"meta":null,"tags":{},"blocked_tags":[],"override_ttl":false,"override_address_records":false,"use_client_subnet":false}"#
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) throws -> (Data, URLResponse) {
        var responseHeaders = headers
        responseHeaders["Content-Type"] = "application/json"
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
}

@MainActor
private final class IBMNS1RecordingTransport: NetworkTransport {
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
