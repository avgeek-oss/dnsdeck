import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class VultrProviderTests: XCTestCase {
    func testListDomainsUsesBearerAuthAndCursorPagination() async throws {
        let transport = VultrRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer vultr-key")
            XCTAssertEqual(request.url?.path, "/v2/domains")
            if index == 0 {
                XCTAssertEqual(request.url?.query, "per_page=500")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"domains":[{"domain":"one.example","date_created":"2026-07-10T00:00:00+00:00","dns_sec":"disabled"}],"meta":{"total":2,"links":{"next":"next-cursor","prev":""}}}"#
                )
            }
            XCTAssertEqual(request.url?.query, "per_page=500&cursor=next-cursor")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"domains":[{"domain":"two.example","dns_sec":"enabled"}],"meta":{"total":2,"links":{"next":"","prev":"previous"}}}"#
            )
        }

        let domains = try await makeService(transport: transport).listDomains()

        XCTAssertEqual(domains.map(\.domain), ["one.example", "two.example"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testDomainCreateDetailsAndDeleteContracts() async throws {
        let body = #"{"domain":{"domain":"example.com","date_created":"2026-07-10T00:00:00+00:00","dns_sec":"disabled"}}"#
        let transport = VultrRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v2/domains")
                XCTAssertEqual(
                    try JSONDecoder().decode(VultrCreateDomainRequest.self, from: XCTUnwrap(request.httpBody)),
                    VultrCreateDomainRequest(domain: "example.com")
                )
                return try Self.response(request: request, status: 200, body: body)
            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com")
                return try Self.response(request: request, status: 200, body: body)
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com")
                return try Self.response(request: request, status: 204, body: "")
            }
        }
        let service = makeService(transport: transport)

        let created = try await service.createDomain(name: "example.com")
        let fetched = try await service.getDomain(name: created.domain)
        try await service.deleteDomain(name: created.domain)

        XCTAssertEqual(created, fetched)
        XCTAssertEqual(created.snapshot(nameservers: VultrService.nameservers).nameservers, VultrService.nameservers)
    }

    func testRecordCRUDUsesPostPatchDeleteAndPreservesEmptyApexName() async throws {
        let create = VultrRecordCreateRequest(
            name: "",
            type: "CAA",
            data: "0 issue letsencrypt.org",
            ttl: 300,
            priority: nil
        )
        let update = VultrRecordUpdateRequest(name: "www", data: "0 issue pki.goog", ttl: 3600, priority: nil)
        let recordBody = #"{"record":{"id":"record-id","type":"CAA","name":"","data":"0 issue letsencrypt.org","priority":0,"ttl":300}}"#
        let transport = VultrRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com/records")
                let data = try XCTUnwrap(request.httpBody)
                XCTAssertEqual(try JSONDecoder().decode(VultrRecordCreateRequest.self, from: data), create)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertTrue(object.keys.contains("name"))
                XCTAssertEqual(object["name"] as? String, "")
                return try Self.response(request: request, status: 201, body: recordBody)
            case 1:
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com/records/record-id")
                XCTAssertEqual(
                    try JSONDecoder().decode(VultrRecordUpdateRequest.self, from: XCTUnwrap(request.httpBody)),
                    update
                )
                return try Self.response(request: request, status: 204, body: "")
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com/records/record-id")
                return try Self.response(request: request, status: 204, body: "")
            }
        }
        let service = makeService(transport: transport)

        _ = try await service.createRecord(domain: "example.com", request: create)
        try await service.updateRecord(domain: "example.com", recordId: "record-id", request: update)
        try await service.deleteRecord(domain: "example.com", recordId: "record-id")
    }

    func testListRecordsPaginatesAndSnapshotsNativePriorityFields() async throws {
        let transport = VultrRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 200,
                body: #"{"records":[{"id":"srv","type":"SRV","name":"_sip._tcp.example.com","data":"20 5060 sip.example.com.","priority":10,"ttl":300},{"id":"mx","type":"MX","name":"","data":"mail.example.com.","priority":5,"ttl":3600}],"meta":{"total":2,"links":{"next":"","prev":""}}}"#
            )
        }

        let records = try await makeService(transport: transport).listRecords(domain: "example.com")
        let srv = records[0].snapshot(zoneName: "example.com")
        let mx = records[1].snapshot(zoneName: "example.com")

        XCTAssertEqual(srv.name, "_sip._tcp")
        XCTAssertEqual(srv.content, "10 20 5060 sip.example.com.")
        XCTAssertEqual(srv.priority, 10)
        XCTAssertEqual(mx.name, "@")
        XCTAssertEqual(mx.priority, 5)
        XCTAssertNotNil(srv.providerData)
    }

    func testRequestMappingSeparatesMXAndSRVPriority() throws {
        let srv = try CreateProviderRecordRequest(
            name: "_sip._tcp.example.com",
            type: "SRV",
            content: "10 20 5060 sip.example.com.",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toVultrRequest(zoneName: "example.com")
        XCTAssertEqual(srv.name, "_sip._tcp")
        XCTAssertEqual(srv.priority, 10)
        XCTAssertEqual(srv.data, "20 5060 sip.example.com.")

        let mx = try CreateProviderRecordRequest(
            name: "@",
            type: "MX",
            content: "5 mail.example.com.",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toVultrRequest(zoneName: "example.com")
        XCTAssertEqual(mx.name, "")
        XCTAssertEqual(mx.priority, 5)
        XCTAssertEqual(mx.data, "mail.example.com.")
    }

    func testUpdateIsPartialAndRejectsTypeChanges() throws {
        let existing = VultrDomainRecord(
            id: "record-id",
            type: "A",
            name: "www",
            data: "192.0.2.1",
            priority: 0,
            ttl: 300
        )
        let request = try UpdateProviderRecordRequest(name: "@", ttl: 3600)
            .toVultrRequest(zoneName: "example.com", existing: existing)
        XCTAssertEqual(request.name, "")
        XCTAssertNil(request.data)
        XCTAssertEqual(request.ttl, 3600)

        XCTAssertThrowsError(
            try UpdateProviderRecordRequest(type: "AAAA")
                .toVultrRequest(zoneName: "example.com", existing: existing)
        )
    }

    private func makeService(transport: VultrRecordingTransport) -> VultrService {
        VultrService(
            tokenProvider: { "vultr-key" },
            baseURL: URL(string: "https://api.vultr.test/v2")!,
            transport: transport,
            sleep: { _ in }
        )
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
private final class VultrRecordingTransport: NetworkTransport {
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
