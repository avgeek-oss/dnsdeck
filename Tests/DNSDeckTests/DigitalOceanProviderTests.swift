import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class DigitalOceanProviderTests: XCTestCase {
    func testListDomainsPaginatesOnTrustedOriginAndAuthenticates() async throws {
        let transport = DigitalOceanRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dop_v1_test")
            XCTAssertEqual(request.url?.host, "api.digitalocean.test")

            if index == 0 {
                XCTAssertEqual(request.url?.query, "per_page=200")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"domains":[{"name":"one.example","ttl":1800,"zone_file":"zone"}],"links":{"pages":{"next":"https://api.digitalocean.test/v2/domains?page=2&per_page=200"}}}"#
                )
            }

            XCTAssertEqual(request.url?.query, "page=2&per_page=200")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"domains":[{"name":"two.example","ttl":1800,"zone_file":"zone"}],"links":{}}"#
            )
        }
        let service = makeService(transport: transport)

        let domains = try await service.listDomains()

        XCTAssertEqual(domains.map(\.name), ["one.example", "two.example"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testListDomainsRejectsCrossOriginPaginationURL() async throws {
        let transport = DigitalOceanRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 200,
                body: #"{"domains":[],"links":{"pages":{"next":"https://attacker.example/steal"}}}"#
            )
        }
        let service = makeService(transport: transport)

        do {
            _ = try await service.listDomains()
            XCTFail("Expected an untrusted pagination URL error")
        } catch let ProviderAPIError.untrustedURL(provider, url) {
            XCTAssertEqual(provider, .digitalOcean)
            XCTAssertEqual(url.host, "attacker.example")
        }

        XCTAssertEqual(transport.requests.count, 1)
    }

    func testReadRetriesRateLimitUsingRetryAfter() async throws {
        var delays: [TimeInterval] = []
        let transport = DigitalOceanRecordingTransport { request, index in
            if index == 0 {
                return try Self.response(
                    request: request,
                    status: 429,
                    body: #"{"id":"too_many_requests","message":"API rate limit exceeded.","request_id":"request-1"}"#,
                    headers: ["Retry-After": "2"]
                )
            }
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"domains":[],"links":{}}"#
            )
        }
        let service = makeService(transport: transport) { delays.append($0) }

        _ = try await service.listDomains()

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(delays, [2])
    }

    func testDomainCreateDetailsAndDeleteContracts() async throws {
        let transport = DigitalOceanRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v2/domains")
                XCTAssertEqual(
                    try JSONDecoder().decode(DigitalOceanCreateDomainRequest.self, from: XCTUnwrap(request.httpBody)),
                    DigitalOceanCreateDomainRequest(name: "example.com")
                )
                return try Self.response(
                    request: request,
                    status: 201,
                    body: #"{"domain":{"name":"example.com","ttl":1800,"zone_file":"zone"}}"#
                )
            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"domain":{"name":"example.com","ttl":1800,"zone_file":"zone"}}"#
                )
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com")
                return try Self.response(request: request, status: 204, body: "")
            }
        }
        let service = makeService(transport: transport)

        let created = try await service.createDomain(name: "example.com")
        let fetched = try await service.getDomain(name: "example.com")
        try await service.deleteDomain(name: "example.com")

        XCTAssertEqual(created, fetched)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testRecordCRUDUsesDocumentedMethodsPathsAndBodies() async throws {
        let nativeRecord = #"{"id":28448433,"type":"A","name":"www","data":"162.10.66.0","priority":null,"port":null,"ttl":1800,"weight":null,"flags":null,"tag":null}"#
        let create = DigitalOceanRecordWriteRequest(
            type: "A",
            name: "www",
            data: "162.10.66.0",
            priority: nil,
            port: nil,
            ttl: 1800,
            weight: nil,
            flags: nil,
            tag: nil
        )
        let update = DigitalOceanRecordWriteRequest(
            type: "A",
            name: "blog",
            data: "162.10.66.0",
            priority: nil,
            port: nil,
            ttl: 3600,
            weight: nil,
            flags: nil,
            tag: nil
        )
        let transport = DigitalOceanRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com/records")
                XCTAssertEqual(
                    try JSONDecoder().decode(DigitalOceanRecordWriteRequest.self, from: XCTUnwrap(request.httpBody)),
                    create
                )
                return try Self.response(
                    request: request,
                    status: 201,
                    body: "{\"domain_record\":\(nativeRecord)}"
                )
            case 1:
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com/records/28448433")
                XCTAssertEqual(
                    try JSONDecoder().decode(DigitalOceanRecordWriteRequest.self, from: XCTUnwrap(request.httpBody)),
                    update
                )
                return try Self.response(
                    request: request,
                    status: 200,
                    body: "{\"domain_record\":\(nativeRecord)}"
                )
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v2/domains/example.com/records/28448433")
                return try Self.response(request: request, status: 204, body: "")
            }
        }
        let service = makeService(transport: transport)

        _ = try await service.createRecord(domain: "example.com", request: create)
        _ = try await service.updateRecord(domain: "example.com", recordId: 28_448_433, request: update)
        try await service.deleteRecord(domain: "example.com", recordId: 28_448_433)

        XCTAssertEqual(transport.requests.count, 3)
    }

    func testNativeSRVAndCAAMappingRoundTripsAllProviderFields() throws {
        let srv = DigitalOceanDomainRecord(
            id: 1,
            type: "SRV",
            name: "_sip._tcp",
            data: "sip.example.com.",
            priority: 10,
            port: 5060,
            ttl: 1800,
            weight: 20,
            flags: nil,
            tag: nil
        )
        let caa = DigitalOceanDomainRecord(
            id: 2,
            type: "CAA",
            name: "@",
            data: "letsencrypt.org",
            priority: nil,
            port: nil,
            ttl: 1800,
            weight: nil,
            flags: 0,
            tag: "issue"
        )

        XCTAssertEqual(srv.snapshot().content, "10 20 5060 sip.example.com.")
        XCTAssertEqual(caa.snapshot().content, "0 issue letsencrypt.org")
        XCTAssertNotNil(srv.snapshot().providerData)

        let update = try UpdateProviderRecordRequest(ttl: 3600)
            .toDigitalOceanRequest(zoneName: "example.com", existingRecord: srv)
        XCTAssertEqual(update.priority, 10)
        XCTAssertEqual(update.weight, 20)
        XCTAssertEqual(update.port, 5060)
        XCTAssertEqual(update.data, "sip.example.com.")
        XCTAssertEqual(update.ttl, 3600)
    }

    func testCreateRequestsMapRelativeNamesAndStructuredFields() throws {
        let srv = try CreateProviderRecordRequest(
            name: "_sip._tcp.example.com",
            type: "SRV",
            content: "",
            ttl: 1800,
            proxied: nil,
            priority: nil,
            comment: nil,
            recordData: RecordData(
                service: "_sip",
                proto: "_tcp",
                name: "example.com",
                priority: 10,
                weight: 20,
                port: 5060,
                target: "sip.example.com."
            )
        ).toDigitalOceanRequest(zoneName: "example.com")

        XCTAssertEqual(srv.name, "_sip._tcp")
        XCTAssertEqual(srv.data, "sip.example.com.")
        XCTAssertEqual(srv.priority, 10)
        XCTAssertEqual(srv.weight, 20)
        XCTAssertEqual(srv.port, 5060)
    }

    func testHTTPErrorIncludesProviderMessageAndRequestID() async throws {
        let transport = DigitalOceanRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 401,
                body: #"{"id":"unauthorized","message":"Unable to authenticate you.","request_id":"request-42"}"#
            )
        }
        let service = makeService(transport: transport)

        do {
            _ = try await service.listDomains()
            XCTFail("Expected authentication failure")
        } catch let ProviderAPIError.http(provider, statusCode, message, requestId, _) {
            XCTAssertEqual(provider, .digitalOcean)
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "Unable to authenticate you.")
            XCTAssertEqual(requestId, "request-42")
        }
    }

    func testAdapterExposesNameserversAndZoneDeletion() async throws {
        let environmentId = UUID()
        let transport = DigitalOceanRecordingTransport { request, index in
            if index == 0 {
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"domains":[{"name":"example.com","ttl":1800,"zone_file":"zone"}],"links":{}}"#
                )
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v2/domains/example.com")
            return try Self.response(request: request, status: 204, body: "")
        }
        let adapter = DigitalOceanDNSProviderService(service: makeService(transport: transport))

        let zones = try await adapter.listZones(environmentId: environmentId)
        let zone = try XCTUnwrap(zones.first)
        XCTAssertEqual(zone.nameservers, DigitalOceanService.nameservers)
        try await adapter.deleteZone(zone)

        XCTAssertEqual(transport.requests.count, 2)
    }

    private func makeService(
        transport: DigitalOceanRecordingTransport,
        sleep: @escaping ProviderHTTPClient.Sleep = { _ in }
    ) -> DigitalOceanService {
        DigitalOceanService(
            tokenProvider: { "dop_v1_test" },
            baseURL: URL(string: "https://api.digitalocean.test/v2")!,
            transport: transport,
            sleep: sleep
        )
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) throws -> (Data, URLResponse) {
        var responseHeaders = ["Content-Type": "application/json"]
        responseHeaders.merge(headers) { _, new in new }
        let response = try XCTUnwrap(
            try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: responseHeaders
            )
        )
        return (Data(body.utf8), response)
    }
}

@MainActor
private final class DigitalOceanRecordingTransport: NetworkTransport {
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
