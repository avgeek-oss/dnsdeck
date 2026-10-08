import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class DeSECProviderTests: XCTestCase {
    func testDomainPaginationUsesTokenAndFollowsSameOriginLink() async throws {
        let transport = DeSECRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token desec-token")
            XCTAssertTrue(request.url?.absoluteString.hasPrefix("https://desec.test/api/v1/domains/") == true)
            if index == 0 {
                XCTAssertEqual(request.url?.query, "cursor=")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"[{"name":"one.example","minimum_ttl":3600}]"#,
                    headers: [
                        "Link": #"<https://desec.test/api/v1/domains/?cursor=opaque-next>; rel="next""#,
                    ]
                )
            }
            XCTAssertEqual(request.url?.query, "cursor=opaque-next")
            return try Self.response(
                request: request,
                status: 200,
                body: #"[{"name":"two.example","minimum_ttl":60}]"#
            )
        }

        let domains = try await makeService(transport: transport).listDomains()

        XCTAssertEqual(domains.map(\.name), ["one.example", "two.example"])
        XCTAssertEqual(domains.map(\.minimumTTL), [3600, 60])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testPaginationRejectsCrossOriginNextLink() async throws {
        let transport = DeSECRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 200,
                body: "[]",
                headers: ["Link": #"<https://attacker.example/api/v1/domains/?cursor=stolen>; rel="next""#]
            )
        }

        do {
            _ = try await makeService(transport: transport).listDomains()
            XCTFail("Expected an invalid pagination URL")
        } catch let ProviderAPIError.invalidURL(provider) {
            XCTAssertEqual(provider, .deSEC)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testDomainCRUDUsesDocumentedTrailingSlashEndpoints() async throws {
        let transport = DeSECRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.absoluteString, "https://desec.test/api/v1/domains/")
                XCTAssertEqual(
                    try JSONDecoder().decode(DeSECCreateDomainRequest.self, from: XCTUnwrap(request.httpBody)),
                    DeSECCreateDomainRequest(name: "example.com")
                )
                return try Self.response(
                    request: request,
                    status: 201,
                    body: #"{"name":"example.com","minimum_ttl":3600,"created":"2026-07-10T12:00:00.123456Z"}"#
                )
            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.absoluteString, "https://desec.test/api/v1/domains/example.com/")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"name":"example.com","minimum_ttl":3600}"#
                )
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.absoluteString, "https://desec.test/api/v1/domains/example.com/")
                return try Self.response(request: request, status: 204, body: "")
            }
        }
        let service = makeService(transport: transport)

        let created = try await service.createDomain(name: "example.com")
        let fetched = try await service.getDomain(name: created.name)
        try await service.deleteDomain(name: fetched.name)

        XCTAssertNotNil(created.snapshot().createdOn)
        XCTAssertEqual(created.snapshot().nameservers, ["ns1.desec.io", "ns2.desec.org"])
    }

    func testRRsetCRUDUsesCollectionPostItemPutAndApexAtPath() async throws {
        let request = DeSECRRsetWriteRequest(
            subname: "",
            type: "TXT",
            ttl: 3600,
            records: [#""verification value""#]
        )
        let transport = DeSECRecordingTransport { urlRequest, index in
            switch index {
            case 0:
                XCTAssertEqual(urlRequest.httpMethod, "POST")
                XCTAssertEqual(urlRequest.url?.absoluteString, "https://desec.test/api/v1/domains/example.com/rrsets/")
            case 1:
                XCTAssertEqual(urlRequest.httpMethod, "PUT")
                XCTAssertEqual(
                    urlRequest.url?.absoluteString,
                    "https://desec.test/api/v1/domains/example.com/rrsets/@/TXT/"
                )
            default:
                XCTAssertEqual(urlRequest.httpMethod, "DELETE")
                XCTAssertEqual(
                    urlRequest.url?.absoluteString,
                    "https://desec.test/api/v1/domains/example.com/rrsets/@/TXT/"
                )
                return try Self.response(request: urlRequest, status: 204, body: "")
            }
            XCTAssertEqual(
                try JSONDecoder().decode(DeSECRRsetWriteRequest.self, from: XCTUnwrap(urlRequest.httpBody)),
                request
            )
            return try Self.response(request: urlRequest, status: 200, body: "{}")
        }
        let service = makeService(transport: transport)

        try await service.createRRset(domain: "example.com", request: request)
        try await service.replaceRRset(domain: "example.com", request: request)
        try await service.deleteRRset(domain: "example.com", subname: "", type: "TXT")
    }

    func testMutationUsesDomainMinimumAndPreservesMultiValueRRset() throws {
        let mutation = try CreateProviderRecordRequest(
            name: "www.example.com.",
            type: "MX",
            content: "mail.example.com.",
            ttl: 60,
            proxied: nil,
            priority: 20,
            comment: nil,
            values: ["mail-a.example.com.", "30 mail-b.example.com."]
        ).toDeSECMutation(zoneName: "example.com", minimumTTL: 300)

        XCTAssertEqual(mutation.request.subname, "www")
        XCTAssertEqual(mutation.request.ttl, 300)
        XCTAssertEqual(mutation.request.records, ["20 mail-a.example.com.", "30 mail-b.example.com."])

        let capped = try CreateProviderRecordRequest(
            name: "@",
            type: "TXT",
            content: "verification value",
            ttl: 100_000,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toDeSECMutation(zoneName: "example.com", minimumTTL: 3600)
        XCTAssertEqual(capped.request.subname, "")
        XCTAssertEqual(capped.request.ttl, 86400)
        XCTAssertEqual(capped.request.records, [#""verification value""#])
    }

    func testSnapshotNormalizesTXTAndMXAndProtectsApexNS() {
        let txt = DeSECRRset(
            created: nil,
            domain: "example.com",
            subname: "www",
            name: "www.example.com.",
            type: "TXT",
            records: [#""first" "second""#],
            ttl: 3600,
            touched: nil
        ).snapshot()
        let mx = DeSECRRset(
            created: nil,
            domain: "example.com",
            subname: "",
            name: "example.com.",
            type: "MX",
            records: ["10 mail.example.com."],
            ttl: 3600,
            touched: nil
        ).snapshot()
        let ns = DeSECRRset(
            created: nil,
            domain: "example.com",
            subname: "",
            name: "example.com.",
            type: "NS",
            records: ["ns1.desec.io.", "ns2.desec.org."],
            ttl: 86400,
            touched: nil
        ).snapshot()

        XCTAssertEqual(txt.values, ["firstsecond"])
        XCTAssertEqual(mx.values, ["mail.example.com."])
        XCTAssertEqual(mx.priority, 10)
        XCTAssertEqual(ns.metadata["isProtected"], "true")
        XCTAssertNotNil(txt.providerData)
    }

    func testAdapterRejectsApexNSBeforeNetwork() async throws {
        let transport = DeSECRecordingTransport { _, _ in
            XCTFail("Protected records must be rejected before a request")
            throw URLError(.badServerResponse)
        }
        let adapter = DeSECDNSProviderService(service: makeService(transport: transport))
        let domain = DeSECDomain(name: "example.com", minimumTTL: 3600, created: nil, published: nil, touched: nil)
        let rrset = DeSECRRset(
            created: nil,
            domain: domain.name,
            subname: "",
            name: "example.com.",
            type: "NS",
            records: ["ns1.desec.io.", "ns2.desec.org."],
            ttl: 86400,
            touched: nil
        )
        let zone = ProviderZone(provider: .deSEC, snapshot: domain.snapshot(), environmentId: UUID())
        let record = ProviderRecord(provider: .deSEC, snapshot: rrset.snapshot())

        do {
            try await adapter.deleteRecord(in: zone, record: record)
            XCTFail("Expected a read-only record error")
        } catch let ProviderOperationError.readOnlyRecord(provider, _) {
            XCTAssertEqual(provider, .deSEC)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func makeService(transport: DeSECRecordingTransport) -> DeSECService {
        DeSECService(
            tokenProvider: { "desec-token" },
            baseURL: URL(string: "https://desec.test/api/v1")!,
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
private final class DeSECRecordingTransport: NetworkTransport {
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
