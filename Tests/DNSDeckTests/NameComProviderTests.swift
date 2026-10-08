import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class NameComProviderTests: XCTestCase {
    func testListDomainsUsesCoreV1BasicAuthAndBoundedPagination() async throws {
        let transport = NameComRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/core/v1/domains")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic dXNlcjp0b2tlbg==")
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                .queryItems ?? []
            XCTAssertEqual(query.first(where: { $0.name == "page" })?.value, String(index + 1))
            XCTAssertEqual(query.first(where: { $0.name == "perPage" })?.value, "1000")
            let nextPage = index == 0 ? ",\"nextPage\":2,\"lastPage\":2" : ""
            return try Self.response(
                request: request,
                status: 200,
                body: "{\"domains\":[{\"domainName\":\"page-\(index + 1).example\"}],\"from\":1,\"to\":1,\"totalCount\":2\(nextPage)}"
            )
        }

        let domains = try await makeService(transport: transport).listDomains()

        XCTAssertEqual(domains.map(\.domainName), ["page-1.example", "page-2.example"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testListRecordsPreservesNativeFieldsAndAliases() async throws {
        let transport = NameComRecordingTransport { request, _ in
            XCTAssertEqual(request.url?.path, "/core/v1/domains/example.com/records")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"records":[{"answer":"edge.example.net.","domainName":"example.com","fqdn":"example.com.","host":"","id":42,"ttl":300,"type":"ANAME"},{"answer":"5 443 sip.example.com.","domainName":"example.com","fqdn":"_sip._tcp.example.com.","host":"_sip._tcp","id":43,"priority":10,"ttl":600,"type":"SRV"}],"from":1,"to":2,"totalCount":2}"#
            )
        }

        let records = try await makeService(transport: transport).listRecords(domain: "example.com")

        XCTAssertEqual(records[0].snapshot().name, "example.com")
        XCTAssertEqual(records[0].snapshot().aliasTarget?.name, "edge.example.net.")
        XCTAssertEqual(records[1].snapshot().priority, 10)
        XCTAssertEqual(records[1].snapshot().values, ["5 443 sip.example.com."])
        XCTAssertNotNil(records[1].snapshot().providerData)
    }

    func testZoneDetailsUsesDomainNameservers() async throws {
        let transport = NameComRecordingTransport { request, _ in
            XCTAssertEqual(request.url?.path, "/core/v1/domains/example.com")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"domainName":"example.com","locked":true,"nameservers":["ns1.name.com","ns2.name.com"]}"#
            )
        }
        let adapter = NameComDNSProviderService(service: makeService(transport: transport))

        let zone = try await adapter.zoneDetails(for: providerZone())

        XCTAssertEqual(zone.nameservers, ["ns1.name.com", "ns2.name.com"])
    }

    func testCreateUpdateAndDeleteUseIndividualRecordContracts() async throws {
        let create = NameComRecordWriteRequest(
            type: "A",
            host: "www",
            answer: "192.0.2.1",
            ttl: 300,
            priority: nil
        )
        let update = NameComRecordWriteRequest(
            type: "A",
            host: "www",
            answer: "192.0.2.2",
            ttl: 600,
            priority: nil
        )
        let transport = NameComRecordingTransport { request, index in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic dXNlcjp0b2tlbg==")
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/core/v1/domains/example.com/records")
                XCTAssertEqual(
                    try JSONDecoder().decode(NameComRecordWriteRequest.self, from: XCTUnwrap(request.httpBody)),
                    create
                )
                return try Self.recordResponse(request: request, answer: create.answer, ttl: create.ttl)
            }
            if index == 1 {
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path, "/core/v1/domains/example.com/records/42")
                XCTAssertEqual(
                    try JSONDecoder().decode(NameComRecordWriteRequest.self, from: XCTUnwrap(request.httpBody)),
                    update
                )
                return try Self.recordResponse(request: request, answer: update.answer, ttl: update.ttl)
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/core/v1/domains/example.com/records/42")
            return try Self.response(request: request, status: 204, body: "")
        }
        let service = makeService(transport: transport)

        _ = try await service.createRecord(domain: "example.com", request: create)
        _ = try await service.updateRecord(domain: "example.com", recordId: 42, request: update)
        try await service.deleteRecord(domain: "example.com", recordId: 42)

        XCTAssertEqual(transport.requests.count, 3)
    }

    func testMappingsHandleApexTTLFloorMXAndSRV() throws {
        let mx = try CreateProviderRecordRequest(
            name: "example.com.",
            type: "MX",
            content: "20 mail.example.com.",
            ttl: 60,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toNameComRequests(zoneName: "example.com")
        XCTAssertEqual(mx[0].host, "")
        XCTAssertEqual(mx[0].answer, "mail.example.com.")
        XCTAssertEqual(mx[0].priority, 20)
        XCTAssertEqual(mx[0].ttl, 300)

        let srv = try CreateProviderRecordRequest(
            name: "_sip._tcp.example.com",
            type: "SRV",
            content: "10 5 443 sip.example.com.",
            ttl: 600,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toNameComRequests(zoneName: "example.com")
        XCTAssertEqual(srv[0].host, "_sip._tcp")
        XCTAssertEqual(srv[0].answer, "5 443 sip.example.com.")
        XCTAssertEqual(srv[0].priority, 10)
    }

    func testAdapterCreatesEveryRequestedValue() async throws {
        let transport = NameComRecordingTransport { request, index in
            let body = try JSONDecoder().decode(NameComRecordWriteRequest.self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body.answer, index == 0 ? "192.0.2.1" : "192.0.2.2")
            return try Self.recordResponse(request: request, id: index + 1, answer: body.answer, ttl: body.ttl)
        }
        let adapter = NameComDNSProviderService(service: makeService(transport: transport))

        try await adapter.createRecord(
            in: providerZone(),
            payload: CreateProviderRecordRequest(
                name: "www",
                type: "A",
                content: "192.0.2.1",
                ttl: 300,
                proxied: nil,
                priority: nil,
                comment: nil,
                values: ["192.0.2.1", "192.0.2.2"]
            )
        )

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testReadRetriesUsingRateLimitResetEpoch() async throws {
        var delays: [TimeInterval] = []
        let transport = NameComRecordingTransport { request, index in
            if index == 0 {
                return try Self.response(
                    request: request,
                    status: 429,
                    body: #"{"message":"Rate Limit Exceeded"}"#,
                    headers: ["X-RateLimit-Reset": "1002"]
                )
            }
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"domains":[],"from":0,"to":0,"totalCount":0}"#
            )
        }
        let service = try NameComService(
            credentialsProvider: { (username: "user", token: "token") },
            baseURL: XCTUnwrap(URL(string: "https://api.name.test")),
            transport: transport,
            sleep: { delays.append($0) },
            now: { Date(timeIntervalSince1970: 1000) }
        )

        _ = try await service.listDomains()

        XCTAssertEqual(delays, [2])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testStructuredErrorIncludesDetailsAndDoesNotRetryWrite() async throws {
        let transport = NameComRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 409,
                body: #"{"message":"Duplicate record","details":"An identical record already exists."}"#
            )
        }
        let service = makeService(transport: transport)

        do {
            _ = try await service.createRecord(
                domain: "example.com",
                request: NameComRecordWriteRequest(
                    type: "A",
                    host: "www",
                    answer: "192.0.2.1",
                    ttl: 300,
                    priority: nil
                )
            )
            XCTFail("Expected duplicate-record error")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .nameCom)
            XCTAssertEqual(statusCode, 409)
            XCTAssertEqual(message, "Duplicate record\nAn identical record already exists.")
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    private func makeService(transport: NameComRecordingTransport) -> NameComService {
        NameComService(
            credentialsProvider: { (username: "user", token: "token") },
            baseURL: URL(string: "https://api.name.test")!,
            transport: transport,
            sleep: { _ in }
        )
    }

    private func providerZone() -> ProviderZone {
        ProviderZone(
            provider: .nameCom,
            snapshot: NameComDomain(
                domainName: "example.com",
                createDate: nil,
                expireDate: nil,
                autorenewEnabled: nil,
                locked: nil,
                locks: nil,
                privacyEnabled: nil,
                nameservers: nil,
                renewalPrice: nil
            ).snapshot(),
            environmentId: UUID()
        )
    }

    private static func recordResponse(
        request: URLRequest,
        id: Int = 42,
        answer: String,
        ttl: Int
    ) throws -> (Data, URLResponse) {
        try response(
            request: request,
            status: 200,
            body: "{\"answer\":\"\(answer)\",\"domainName\":\"example.com\",\"fqdn\":\"www.example.com.\",\"host\":\"www\",\"id\":\(id),\"ttl\":\(ttl),\"type\":\"A\"}"
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
private final class NameComRecordingTransport: NetworkTransport {
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
