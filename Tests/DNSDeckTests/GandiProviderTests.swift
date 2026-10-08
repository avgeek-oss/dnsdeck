import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class GandiProviderTests: XCTestCase {
    func testListDomainsUsesPATAndTotalCountPagination() async throws {
        let transport = GandiRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gandi-pat")
            XCTAssertEqual(request.url?.path, "/v5/livedns/domains")
            XCTAssertEqual(request.url?.query, "page=\(index + 1)&per_page=100")
            let domain = index == 0 ? "one.example" : "two.example"
            return try Self.response(
                request: request,
                status: 200,
                body: "[{\"fqdn\":\"\(domain)\",\"domain_href\":\"https://api.gandi.test/v5/livedns/domains/\(domain)\",\"domain_records_href\":\"https://api.gandi.test/v5/livedns/domains/\(domain)/records\"}]",
                headers: ["Total-Count": "2"]
            )
        }

        let domains = try await makeService(transport: transport).listDomains()

        XCTAssertEqual(domains.map(\.fqdn), ["one.example", "two.example"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testCreateZoneReloadsDomainAndDomainSpecificNameservers() async throws {
        let transport = GandiRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v5/livedns/domains")
                XCTAssertEqual(
                    try JSONDecoder().decode(GandiCreateDomainRequest.self, from: XCTUnwrap(request.httpBody)),
                    GandiCreateDomainRequest(fqdn: "example.com")
                )
                return try Self.response(request: request, status: 201, body: #"{"message":"created"}"#)
            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v5/livedns/domains/example.com")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"fqdn":"example.com","domain_href":"https://api.gandi.test/v5/livedns/domains/example.com","domain_records_href":"https://api.gandi.test/v5/livedns/domains/example.com/records","domain_keys_href":"https://api.gandi.test/v5/livedns/domains/example.com/keys","automatic_snapshots":true}"#
                )
            default:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v5/livedns/domains/example.com/nameservers")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"["ns-154-a.gandi.net","ns-232-b.gandi.net","ns-109-c.gandi.net"]"#
                )
            }
        }
        let adapter = GandiDNSProviderService(service: makeService(transport: transport))

        let zone = try await adapter.createZone(named: "example.com", environmentId: UUID())

        XCTAssertEqual(zone.name, "example.com")
        XCTAssertEqual(zone.nameservers, ["ns-154-a.gandi.net", "ns-232-b.gandi.net", "ns-109-c.gandi.net"])
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testRecordSetCRUDUsesPostPutDeleteContracts() async throws {
        let create = GandiRecordSetWriteRequest(rrsetValues: ["192.0.2.1", "192.0.2.2"], rrsetTTL: 300)
        let update = GandiRecordSetWriteRequest(rrsetValues: ["192.0.2.3"], rrsetTTL: 3600)
        let transport = GandiRecordingTransport { request, index in
            XCTAssertEqual(request.url?.path, "/v5/livedns/domains/example.com/records/www/A")
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(
                    try JSONDecoder().decode(GandiRecordSetWriteRequest.self, from: XCTUnwrap(request.httpBody)),
                    create
                )
                return try Self.response(request: request, status: 201, body: #"{"message":"created"}"#)
            case 1:
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(
                    try JSONDecoder().decode(GandiRecordSetWriteRequest.self, from: XCTUnwrap(request.httpBody)),
                    update
                )
                return try Self.response(request: request, status: 201, body: #"{"message":"updated"}"#)
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                return try Self.response(request: request, status: 204, body: "")
            }
        }
        let service = makeService(transport: transport)

        try await service.createRecordSet(domain: "example.com", name: "www", type: "A", request: create)
        try await service.replaceRecordSet(domain: "example.com", name: "www", type: "A", request: update)
        try await service.deleteRecordSet(domain: "example.com", name: "www", type: "A")
    }

    func testRecordSnapshotsPreserveSetsAndNormalizeTXTAndMXDisplay() async throws {
        let body = #"[{"rrset_name":"@","rrset_type":"TXT","rrset_values":["\"first\" \"second\"","\"third\""],"rrset_ttl":10800,"rrset_href":"https://api.gandi.test/txt"},{"rrset_name":"@","rrset_type":"MX","rrset_values":["20 mail.example.com."],"rrset_ttl":3600,"rrset_href":"https://api.gandi.test/mx"}]"#
        let transport = GandiRecordingTransport { request, _ in
            try Self.response(request: request, status: 200, body: body, headers: ["Total-Count": "2"])
        }

        let records = try await makeService(transport: transport).listRecordSets(domain: "example.com")
        let txt = records[0].snapshot()
        let mx = records[1].snapshot()

        XCTAssertEqual(txt.values, ["firstsecond", "third"])
        XCTAssertEqual(mx.content, "mail.example.com.")
        XCTAssertEqual(mx.priority, 20)
        XCTAssertEqual(txt.metadata["valueCount"], "2")
        XCTAssertNotNil(txt.providerData)
    }

    func testMappingPreservesMXPriorityAndChunksLongTXT() throws {
        let existingMX = GandiRecordSet(
            rrsetName: "@",
            rrsetType: "MX",
            rrsetValues: ["20 old.example.com."],
            rrsetTTL: 3600,
            rrsetHref: nil
        )
        let mx = try UpdateProviderRecordRequest(content: "new.example.com.")
            .toGandiMutation(zoneName: "example.com", existing: existingMX)
        XCTAssertEqual(mx.request.rrsetValues, ["20 new.example.com."])

        let longValue = String(repeating: "a", count: 300)
        let txt = try CreateProviderRecordRequest(
            name: "@",
            type: "TXT",
            content: longValue,
            ttl: 100,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toGandiMutation(zoneName: "example.com")
        XCTAssertEqual(txt.name, "@")
        XCTAssertEqual(txt.request.rrsetTTL, 300)
        XCTAssertTrue(txt.request.rrsetValues[0].contains("\" \""))
        XCTAssertEqual(txt.request.rrsetValues[0].filter { $0 == "a" }.count, 300)
    }

    func testTXTChunkingKeepsEscapeSequencesWithinByteBoundary() throws {
        let value = String(repeating: "a", count: 254) + "\"\\tail"

        let mutation = try CreateProviderRecordRequest(
            name: "@",
            type: "TXT",
            content: value,
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toGandiMutation(zoneName: "example.com")

        XCTAssertEqual(
            mutation.request.rrsetValues,
            ["\"\(String(repeating: "a", count: 254))\" \"\\\"\\\\tail\""]
        )
    }

    func testRenameCreatesNewSetBeforeDeletingOldSet() async throws {
        let transport = GandiRecordingTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v5/livedns/domains/example.com/records/api/A")
                return try Self.response(request: request, status: 201, body: #"{"message":"created"}"#)
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v5/livedns/domains/example.com/records/www/A")
            return try Self.response(request: request, status: 204, body: "")
        }
        let adapter = GandiDNSProviderService(service: makeService(transport: transport))
        let domain = GandiDomain(
            fqdn: "example.com",
            domainHref: nil,
            domainKeysHref: nil,
            domainRecordsHref: nil,
            automaticSnapshots: true
        )
        let zone = ProviderZone(provider: .gandi, snapshot: domain.snapshot(), environmentId: UUID())
        let set = GandiRecordSet(
            rrsetName: "www",
            rrsetType: "A",
            rrsetValues: ["192.0.2.1"],
            rrsetTTL: 300,
            rrsetHref: nil
        )
        let record = ProviderRecord(provider: .gandi, snapshot: set.snapshot())

        try await adapter.updateRecord(
            in: zone,
            record: record,
            edits: UpdateProviderRecordRequest(name: "api")
        )

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testSOAIsRejectedBeforeNetwork() async throws {
        let transport = GandiRecordingTransport { _, _ in
            XCTFail("SOA should be rejected before a request")
            throw URLError(.badServerResponse)
        }
        let adapter = GandiDNSProviderService(service: makeService(transport: transport))
        let domain = GandiDomain(
            fqdn: "example.com",
            domainHref: nil,
            domainKeysHref: nil,
            domainRecordsHref: nil,
            automaticSnapshots: nil
        )
        let zone = ProviderZone(provider: .gandi, snapshot: domain.snapshot(), environmentId: UUID())
        let soa = GandiRecordSet(
            rrsetName: "@",
            rrsetType: "SOA",
            rrsetValues: ["ns1.example. hostmaster.example. 1 10800 3600 604800 300"],
            rrsetTTL: 10800,
            rrsetHref: nil
        )
        let record = ProviderRecord(provider: .gandi, snapshot: soa.snapshot())

        do {
            try await adapter.deleteRecord(in: zone, record: record)
            XCTFail("Expected read-only record error")
        } catch let ProviderOperationError.readOnlyRecord(provider, _) {
            XCTAssertEqual(provider, .gandi)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testIntegerErrorCodeDoesNotHideGandiMessage() async throws {
        let transport = GandiRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 409,
                body: #"{"cause":"conflict","code":409,"message":"This record already exists","object":"record"}"#
            )
        }

        do {
            try await makeService(transport: transport).createRecordSet(
                domain: "example.com",
                name: "www",
                type: "A",
                request: GandiRecordSetWriteRequest(rrsetValues: ["192.0.2.1"], rrsetTTL: 300)
            )
            XCTFail("Expected API error")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .gandi)
            XCTAssertEqual(statusCode, 409)
            XCTAssertEqual(message, "This record already exists")
        }
    }

    private func makeService(transport: GandiRecordingTransport) -> GandiService {
        GandiService(
            tokenProvider: { "gandi-pat" },
            baseURL: URL(string: "https://api.gandi.test/v5")!,
            transport: transport,
            sleep: { _ in }
        )
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
private final class GandiRecordingTransport: NetworkTransport {
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
