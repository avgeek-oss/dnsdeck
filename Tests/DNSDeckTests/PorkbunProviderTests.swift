import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class PorkbunProviderTests: XCTestCase {
    func testListDomainsUsesHeaderAuthFiltersAndOffsetPagination() async throws {
        let transport = PorkbunRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "porkbun-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Secret-API-Key"), "porkbun-secret")
            XCTAssertEqual(request.url?.path, "/api/json/v3/domain/listAll")
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                .queryItems ?? []
            XCTAssertEqual(query.first(where: { $0.name == "start" })?.value, String(index * 1000))
            XCTAssertNil(query.first(where: { $0.name == "apiAccess" }))
            XCTAssertEqual(query.first(where: { $0.name == "sortName" })?.value, "domain")

            let domains: [PorkbunDomain] = if index == 0 {
                (0 ..< 1000).map {
                    Self.domain(name: String(format: "domain-%04d.example", $0))
                }
            } else {
                [Self.domain(name: "last.example")]
            }
            let response = PorkbunDomainListFixture(status: "SUCCESS", count: domains.count, domains: domains)
            return try Self.response(request: request, status: 200, data: JSONEncoder().encode(response))
        }

        let domains = try await makeService(transport: transport).listDomains()

        XCTAssertEqual(domains.count, 1001)
        XCTAssertEqual(domains.last?.domain, "last.example")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testDomainFlagsDecodeFromNumbersAndStrings() throws {
        let data = Data(
            #"{"domain":"example.com","status":"ACTIVE","securityLock":"1","whoisPrivacy":1,"autoRenew":"0","apiAccess":1,"notLocal":"0"}"#
                .utf8
        )

        let domain = try JSONDecoder().decode(PorkbunDomain.self, from: data)

        XCTAssertEqual(domain.securityLock?.value, 1)
        XCTAssertEqual(domain.whoisPrivacy?.value, 1)
        XCTAssertEqual(domain.autoRenew?.value, 0)
        XCTAssertEqual(domain.apiAccess?.value, 1)
        XCTAssertEqual(domain.notLocal?.value, 0)
        XCTAssertNotNil(domain.snapshot().providerData)
    }

    func testZoneDetailsUsesCurrentDomainAndRegistryNameservers() async throws {
        let transport = PorkbunRecordingTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.url?.path, "/api/json/v3/domain/get/example.com")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"status":"SUCCESS","domain":{"domain":"example.com","status":"ACTIVE","apiAccess":1,"notLocal":0}}"#
                )
            }
            XCTAssertEqual(request.url?.path, "/api/json/v3/domain/getNs/example.com")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"status":"SUCCESS","ns":["curitiba.ns.porkbun.com","fortaleza.ns.porkbun.com"]}"#
            )
        }
        let adapter = PorkbunDNSProviderService(service: makeService(transport: transport))

        let zone = try await adapter.zoneDetails(for: providerZone())

        XCTAssertEqual(zone.nameservers, ["curitiba.ns.porkbun.com", "fortaleza.ns.porkbun.com"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRecordResponsePreservesPriorityNotesAndFlexibleTTL() async throws {
        let transport = PorkbunRecordingTransport { request, _ in
            XCTAssertEqual(request.url?.path, "/api/json/v3/dns/retrieve/example.com")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"status":"SUCCESS","cloudflare":"enabled","records":[{"id":"42","name":"example.com","type":"MX","content":"mail.example.com.","ttl":"600","prio":10,"notes":"primary mail"}]}"#
            )
        }

        let response = try await makeService(transport: transport).listRecords(domain: "example.com")
        let snapshot = try XCTUnwrap(response.records.first).snapshot()

        XCTAssertEqual(response.cloudflare, "enabled")
        XCTAssertEqual(snapshot.ttl, 600)
        XCTAssertEqual(snapshot.priority, 10)
        XCTAssertEqual(snapshot.comment, "primary mail")
        XCTAssertNotNil(snapshot.providerData)
    }

    func testCreateRetriesWithSameIdempotencyKeyAndAuthenticatedBody() async throws {
        let request = PorkbunDNSWriteRequest(
            apiKey: nil,
            secretApiKey: nil,
            name: "www",
            type: "A",
            content: "192.0.2.1",
            ttl: 600,
            prio: nil,
            notes: "web",
            dryRun: nil
        )
        let transport = PorkbunRecordingTransport { urlRequest, index in
            XCTAssertEqual(urlRequest.httpMethod, "POST")
            XCTAssertEqual(urlRequest.url?.path, "/api/json/v3/dns/create/example.com")
            XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Idempotency-Key"), "stable-write-key")
            XCTAssertNil(urlRequest.value(forHTTPHeaderField: "X-API-Key"))
            let body = try JSONDecoder().decode(
                PorkbunDNSWriteRequest.self,
                from: XCTUnwrap(urlRequest.httpBody)
            )
            XCTAssertEqual(body.apiKey, "porkbun-key")
            XCTAssertEqual(body.secretApiKey, "porkbun-secret")
            XCTAssertEqual(body.content, "192.0.2.1")
            if index == 0 {
                return try Self.response(
                    request: urlRequest,
                    status: 503,
                    body: #"{"status":"ERROR","code":"TEMPORARY","message":"try again"}"#,
                    headers: ["Retry-After": "0"]
                )
            }
            return try Self.response(
                request: urlRequest,
                status: 200,
                body: #"{"status":"SUCCESS","id":"9001"}"#
            )
        }

        let id = try await makeService(transport: transport).createRecord(domain: "example.com", request: request)

        XCTAssertEqual(id, "9001")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testEditAndDeleteUseRecordIDContracts() async throws {
        let edit = PorkbunDNSWriteRequest(
            apiKey: nil,
            secretApiKey: nil,
            name: "@",
            type: "TXT",
            content: "verification",
            ttl: 600,
            prio: nil,
            notes: nil,
            dryRun: nil
        )
        let transport = PorkbunRecordingTransport { request, index in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "stable-write-key")
            if index == 0 {
                XCTAssertEqual(request.url?.path, "/api/json/v3/dns/edit/example.com/42")
                let body = try JSONDecoder().decode(PorkbunDNSWriteRequest.self, from: XCTUnwrap(request.httpBody))
                XCTAssertEqual(body.apiKey, "porkbun-key")
                XCTAssertEqual(body.type, "TXT")
            } else {
                XCTAssertEqual(request.url?.path, "/api/json/v3/dns/delete/example.com/42")
                XCTAssertEqual(
                    try JSONDecoder().decode(PorkbunAuthRequest.self, from: XCTUnwrap(request.httpBody)),
                    PorkbunAuthRequest(apiKey: "porkbun-key", secretApiKey: "porkbun-secret")
                )
            }
            return try Self.response(request: request, status: 200, body: #"{"status":"SUCCESS"}"#)
        }
        let service = makeService(transport: transport)

        try await service.updateRecord(domain: "example.com", recordId: "42", request: edit)
        try await service.deleteRecord(domain: "example.com", recordId: "42")

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testMappingsHandleApexAutomaticTTLAndNativePriority() throws {
        let mx = try CreateProviderRecordRequest(
            name: "example.com",
            type: "MX",
            content: "20 mail.example.com.",
            ttl: 1,
            proxied: nil,
            priority: nil,
            comment: "mail"
        ).toPorkbunRequests(zoneName: "example.com")
        XCTAssertEqual(mx.count, 1)
        XCTAssertEqual(mx[0].name, "")
        XCTAssertEqual(mx[0].content, "mail.example.com.")
        XCTAssertEqual(mx[0].prio, 20)
        XCTAssertEqual(mx[0].ttl, 0)

        let srv = try CreateProviderRecordRequest(
            name: "_sip._tcp",
            type: "SRV",
            content: "10 5 443 sip.example.com.",
            ttl: 600,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toPorkbunRequests(zoneName: "example.com")
        XCTAssertEqual(srv[0].content, "5 443 sip.example.com.")
        XCTAssertEqual(srv[0].prio, 10)
    }

    func testAdapterCreatesEveryRequestedValue() async throws {
        let transport = PorkbunRecordingTransport { request, index in
            let body = try JSONDecoder().decode(PorkbunDNSWriteRequest.self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body.content, index == 0 ? "192.0.2.1" : "192.0.2.2")
            return try Self.response(
                request: request,
                status: 200,
                body: "{\"status\":\"SUCCESS\",\"id\":\"\(index + 1)\"}"
            )
        }
        let adapter = PorkbunDNSProviderService(service: makeService(transport: transport))

        try await adapter.createRecord(
            in: providerZone(),
            payload: CreateProviderRecordRequest(
                name: "www",
                type: "A",
                content: "192.0.2.1",
                ttl: 600,
                proxied: nil,
                priority: nil,
                comment: nil,
                values: ["192.0.2.1", "192.0.2.2"]
            )
        )

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testStatusErrorAtHTTP200SurfacesRemediationAndRequestID() async throws {
        let transport = PorkbunRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 200,
                body: #"{"status":"ERROR","code":"API_ACCESS_DISABLED","message":"API access is disabled","requestId":"pb-req-1","next_action":{"type":"enable_setting","hint":"Enable API access for this domain","url":"https://porkbun.com/account"}}"#
            )
        }

        do {
            _ = try await makeService(transport: transport).listRecords(domain: "example.com")
            XCTFail("Expected API status error")
        } catch let ProviderAPIError.http(provider, statusCode, message, requestId, _) {
            XCTAssertEqual(provider, .porkbun)
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(
                message,
                "API access is disabled\nEnable API access for this domain (https://porkbun.com/account)"
            )
            XCTAssertEqual(requestId, "pb-req-1")
        }
    }

    private func makeService(transport: PorkbunRecordingTransport) -> PorkbunService {
        PorkbunService(
            credentialsProvider: { (apiKey: "porkbun-key", secretApiKey: "porkbun-secret") },
            baseURL: URL(string: "https://api.porkbun.test/api/json/v3")!,
            transport: transport,
            sleep: { _ in },
            idempotencyKeyProvider: { "stable-write-key" }
        )
    }

    private func providerZone() -> ProviderZone {
        ProviderZone(
            provider: .porkbun,
            snapshot: Self.domain(name: "example.com").snapshot(),
            environmentId: UUID()
        )
    }

    private static func domain(name: String) -> PorkbunDomain {
        PorkbunDomain(
            domain: name,
            status: "ACTIVE",
            tld: "example",
            createDate: nil,
            expireDate: nil,
            securityLock: PorkbunFlexibleInt(1),
            whoisPrivacy: PorkbunFlexibleInt(1),
            autoRenew: PorkbunFlexibleInt(1),
            apiAccess: PorkbunFlexibleInt(1),
            notLocal: PorkbunFlexibleInt(0)
        )
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) throws -> (Data, URLResponse) {
        try response(request: request, status: status, data: Data(body.utf8), headers: headers)
    }

    private static func response(
        request: URLRequest,
        status: Int,
        data: Data,
        headers: [String: String] = [:]
    ) throws -> (Data, URLResponse) {
        var responseHeaders = headers
        responseHeaders["Content-Type"] = "application/json"
        return try (
            data,
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

private struct PorkbunDomainListFixture: Encodable {
    let status: String
    let count: Int
    let domains: [PorkbunDomain]
}

@MainActor
private final class PorkbunRecordingTransport: NetworkTransport {
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
