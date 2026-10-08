import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class ScalewayProviderTests: XCTestCase {
    func testZonePaginationUsesSecretKeyAndProjectScope() async throws {
        let transport = ScalewayRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Auth-Token"), "scw-secret")
            XCTAssertEqual(request.url?.path, "/domain/v2beta1/dns-zones")
            XCTAssertEqual(request.url?.query, "project_id=project-1&page=\(index + 1)&page_size=100")
            let zone = index == 0 ? Self.zoneFixture(name: "one.example") : Self.zoneFixture(name: "two.example")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"total_count":2,"dns_zones":[\#(zone)]}"#
            )
        }

        let zones = try await makeService(transport: transport).listZones()

        XCTAssertEqual(zones.map(\.name), ["one.example", "two.example"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testZoneCreationIsUnsupportedWithoutSendingARequest() async throws {
        let transport = ScalewayRecordingTransport { _, _ in
            XCTFail("Unsupported operations must not send a request")
            throw URLError(.badURL)
        }
        let adapter = ScalewayDNSProviderService(service: makeService(transport: transport))
        do {
            _ = try await adapter.createZone(named: "prod.eu.example.com", environmentId: UUID())
            XCTFail("Expected unsupported zone creation")
        } catch let ProviderOperationError.unsupportedZoneCreation(provider) {
            XCTAssertEqual(provider, .scaleway)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testDeleteZoneIncludesRequiredProjectID() async throws {
        let transport = ScalewayRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/domain/v2beta1/dns-zones/example.com")
            XCTAssertEqual(request.url?.query, "project_id=project-1")
            return try Self.response(request: request, status: 200, body: "{}")
        }

        try await makeService(transport: transport).deleteZone(name: "example.com")
    }

    func testRecordPaginationPreservesAdvancedConfigurations() async throws {
        let transport = ScalewayRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/domain/v2beta1/dns-zones/example.com/records")
            XCTAssertEqual(request.url?.query, "project_id=project-1&page=\(index + 1)&page_size=100")
            let id = index == 0 ? "record-1" : "record-2"
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"total_count":2,"records":[{"data":"192.0.2.1","name":"www","priority":0,"ttl":300,"type":"A","comment":"web","weighted_config":{"weighted_ips":[{"ip":"192.0.2.1","weight":10}]},"id":"\#(id)","updated_at":"2026-07-10T12:00:00Z"}]}"#
            )
        }

        let records = try await makeService(transport: transport).listRecords(zoneName: "example.com")

        XCTAssertEqual(records.map(\.id), ["record-1", "record-2"])
        XCTAssertNotNil(records[0].weightedConfig)
        XCTAssertEqual(records[0].snapshot().metadata["hasAdvancedConfiguration"], "true")
    }

    func testApplyUsesVersionedChangeEnvelopeAndDisallowsImplicitZoneCreation() async throws {
        let record = ScalewayRecordWrite(
            data: "192.0.2.1",
            name: "www",
            priority: 0,
            ttl: 300,
            type: "A",
            comment: nil,
            geoIPConfig: nil,
            httpServiceConfig: nil,
            weightedConfig: nil,
            viewConfig: nil
        )
        let transport = ScalewayRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/domain/v2beta1/dns-zones/example.com/records")
            XCTAssertEqual(
                try JSONDecoder().decode(ScalewayUpdateRecordsRequest.self, from: XCTUnwrap(request.httpBody)),
                ScalewayUpdateRecordsRequest(
                    changes: [.set(id: "record-1", record: record), .delete(id: "record-2")],
                    returnAllRecords: false,
                    disallowNewZoneCreation: true
                )
            )
            return try Self.response(request: request, status: 200, body: #"{"records":[]}"#)
        }

        try await makeService(transport: transport).apply(
            zoneName: "example.com",
            changes: [.set(id: "record-1", record: record), .delete(id: "record-2")]
        )
    }

    func testUpdatePreservesRoutingConfigAndNormalizesTXT() throws {
        let weighted: [String: ProviderJSONValue] = [
            "weighted_ips": .array([.object(["ip": .string("192.0.2.1"), "weight": .number(10)])]),
        ]
        let existing = ScalewayRecord(
            data: "\"verification value\"",
            name: "",
            priority: 0,
            ttl: 300,
            type: "TXT",
            comment: "ownership",
            geoIPConfig: nil,
            httpServiceConfig: nil,
            weightedConfig: weighted,
            viewConfig: nil,
            id: "record-1",
            updatedAt: nil
        )

        let write = try UpdateProviderRecordRequest(ttl: 600)
            .toScalewayRecord(zoneName: "example.com", existing: existing)

        XCTAssertEqual(write.name, "")
        XCTAssertEqual(write.data, "verification value")
        XCTAssertEqual(write.weightedConfig, weighted)
        XCTAssertEqual(existing.snapshot().name, "@")
        XCTAssertEqual(existing.snapshot().content, "verification value")
    }

    func testTypeChangeDropsIncompatibleAdvancedConfiguration() throws {
        let existing = ScalewayRecord(
            data: "192.0.2.1",
            name: "www",
            priority: 0,
            ttl: 300,
            type: "A",
            comment: nil,
            geoIPConfig: ["default": .string("192.0.2.1")],
            httpServiceConfig: nil,
            weightedConfig: nil,
            viewConfig: nil,
            id: "record-1",
            updatedAt: nil
        )

        let write = try UpdateProviderRecordRequest(type: "CNAME", content: "target.example.com.")
            .toScalewayRecord(zoneName: "example.com", existing: existing)

        XCTAssertNil(write.geoIPConfig)
    }

    func testSRVMappingSeparatesPriorityFromRecordData() throws {
        let structured = try CreateProviderRecordRequest(
            name: "_sip._tcp",
            type: "SRV",
            content: "",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil,
            recordData: RecordData(
                service: "_sip",
                proto: "_tcp",
                name: "example.com",
                priority: 10,
                weight: 5,
                port: 5060,
                target: "sip.example.com.",
                flags: nil,
                tag: nil,
                value: nil
            )
        ).toScalewayRecord(zoneName: "example.com")
        XCTAssertEqual(structured.priority, 10)
        XCTAssertEqual(structured.data, "5 5060 sip.example.com.")

        let presentation = try CreateProviderRecordRequest(
            name: "_sip._tcp",
            type: "SRV",
            content: "20 10 5061 backup.example.com.",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toScalewayRecord(zoneName: "example.com")
        XCTAssertEqual(presentation.priority, 20)
        XCTAssertEqual(presentation.data, "10 5061 backup.example.com.")
    }

    func testTypeChangeRequiresReplacementContent() throws {
        let existing = ScalewayRecord(
            data: "192.0.2.1",
            name: "www",
            priority: 0,
            ttl: 300,
            type: "A",
            comment: nil,
            geoIPConfig: nil,
            httpServiceConfig: nil,
            weightedConfig: nil,
            viewConfig: nil,
            id: "record-1",
            updatedAt: nil
        )

        XCTAssertThrowsError(
            try UpdateProviderRecordRequest(type: "AAAA")
                .toScalewayRecord(zoneName: "example.com", existing: existing)
        )
    }

    func testSecondaryZoneIsReadOnlyBeforeNetwork() async throws {
        let transport = ScalewayRecordingTransport { _, _ in
            XCTFail("A secondary zone mutation must not reach the network")
            throw URLError(.badServerResponse)
        }
        let adapter = ScalewayDNSProviderService(service: makeService(transport: transport))
        let zoneData = ScalewayDNSZone(
            domain: "example.com",
            subdomain: "",
            ns: ["secondary.example.net"],
            nsDefault: [],
            nsMaster: ["192.0.2.53"],
            status: "active",
            message: nil,
            updatedAt: nil,
            projectId: "project-1",
            linkedProducts: nil
        )
        let zone = ProviderZone(provider: .scaleway, snapshot: zoneData.snapshot(), environmentId: UUID())

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
            XCTAssertEqual(provider, .scaleway)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func makeService(transport: ScalewayRecordingTransport) -> ScalewayService {
        ScalewayService(
            credentialsProvider: { (secretKey: "scw-secret", projectId: "project-1") },
            baseURL: URL(string: "https://scaleway.test/domain/v2beta1")!,
            transport: transport,
            sleep: { _ in }
        )
    }

    private static func zoneFixture(name: String) -> String {
        let labels = name.split(separator: ".")
        let domain = labels.suffix(2).joined(separator: ".")
        let subdomain = labels.dropLast(2).joined(separator: ".")
        return #"{"domain":"\#(domain)","subdomain":"\#(subdomain)","ns":["ns0.dom.scw.cloud","ns1.dom.scw.cloud"],"ns_default":["ns0.dom.scw.cloud","ns1.dom.scw.cloud"],"ns_master":[],"status":"active","message":null,"updated_at":"2026-07-10T12:00:00Z","project_id":"project-1"}"#
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
private final class ScalewayRecordingTransport: NetworkTransport {
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
