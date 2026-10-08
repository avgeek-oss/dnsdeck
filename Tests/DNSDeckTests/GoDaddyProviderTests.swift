import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class GoDaddyProviderTests: XCTestCase {
    func testListDomainsUsesBearerTokenShopperAndMarkerPagination() async throws {
        let transport = GoDaddyRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Shopper-Id"), "shopper-42")
            XCTAssertEqual(request.url?.path, "/v1/domains")
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                .queryItems ?? []
            XCTAssertTrue(query.contains(URLQueryItem(name: "statuses", value: "ACTIVE")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "limit", value: "1000")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "includes", value: "nameServers")))

            let domains: [GoDaddyDomain]
            if index == 0 {
                XCTAssertNil(query.first(where: { $0.name == "marker" }))
                domains = (0 ..< 1000).map {
                    GoDaddyDomain(
                        domain: String(format: "domain-%04d.example", $0),
                        domainId: Double($0),
                        status: "ACTIVE",
                        nameServers: ["ns1.domaincontrol.com", "ns2.domaincontrol.com"],
                        createdAt: nil
                    )
                }
            } else {
                XCTAssertEqual(query.first(where: { $0.name == "marker" })?.value, "domain-0999.example")
                domains = [
                    GoDaddyDomain(
                        domain: "last.example",
                        domainId: 1000,
                        status: "ACTIVE",
                        nameServers: ["ns1.domaincontrol.com", "ns2.domaincontrol.com"],
                        createdAt: nil
                    ),
                ]
            }
            return try Self.response(request: request, status: 200, data: JSONEncoder().encode(domains))
        }

        let domains = try await makeService(transport: transport).listDomains()

        XCTAssertEqual(domains.count, 1001)
        XCTAssertEqual(domains.last?.domain, "last.example")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRecordListUsesOffsetPagination() async throws {
        let transport = GoDaddyRecordingTransport { request, index in
            XCTAssertEqual(request.url?.path, "/v1/domains/example.com/records")
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
                .queryItems ?? []
            XCTAssertEqual(query.first(where: { $0.name == "offset" })?.value, String(index * 500))
            XCTAssertEqual(query.first(where: { $0.name == "limit" })?.value, "500")
            let records = index == 0
                ? (0 ..< 500).map { Self.record(name: "host-\($0)", data: "192.0.2.1") }
                : [Self.record(name: "last", data: "192.0.2.2")]
            return try Self.response(request: request, status: 200, data: JSONEncoder().encode(records))
        }

        let records = try await makeService(transport: transport).listRecords(domain: "example.com")

        XCTAssertEqual(records.count, 501)
        XCTAssertEqual(records.last?.name, "last")
    }

    func testAddReplaceAndDeleteUseDocumentedRecordSetContracts() async throws {
        let full = GoDaddyWriteRecord(
            type: "MX",
            name: "@",
            data: "mail.example.com.",
            ttl: 3600,
            priority: 10,
            service: nil,
            recordProtocol: nil,
            port: nil,
            weight: nil
        )
        let transport = GoDaddyRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertEqual(request.url?.path, "/v1/domains/example.com/records")
                XCTAssertEqual(
                    try JSONDecoder().decode([GoDaddyWriteRecord].self, from: XCTUnwrap(request.httpBody)),
                    [full]
                )
                return try Self.response(request: request, status: 200, body: "")
            case 1:
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path, "/v1/domains/example.com/records/MX/@")
                let replacement = try JSONDecoder().decode(
                    [GoDaddyWriteRecord].self,
                    from: XCTUnwrap(request.httpBody)
                )
                XCTAssertNil(replacement[0].type)
                XCTAssertNil(replacement[0].name)
                XCTAssertEqual(replacement[0].priority, 10)
                return try Self.response(request: request, status: 200, body: "")
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v1/domains/example.com/records/MX/@")
                return try Self.response(request: request, status: 204, body: "")
            }
        }
        let service = makeService(transport: transport)

        try await service.addRecords(domain: "example.com", records: [full])
        try await service.replaceRecords(domain: "example.com", type: "MX", name: "@", records: [full])
        try await service.deleteRecordSet(domain: "example.com", type: "MX", name: "@")

        XCTAssertEqual(transport.requests.count, 3)
    }

    func testRecordGroupingPreservesMXAndSeparateSRVIdentities() {
        let records = [
            Self.record(type: "MX", name: "@", data: "mx1.example.", priority: 10),
            Self.record(type: "MX", name: "@", data: "mx2.example.", priority: 20),
            Self.record(
                type: "SRV",
                name: "@",
                data: "sip.example.",
                priority: 10,
                service: "_sip",
                recordProtocol: "_tcp",
                port: 443,
                weight: 5
            ),
            Self.record(
                type: "SRV",
                name: "@",
                data: "xmpp.example.",
                priority: 20,
                service: "_xmpp",
                recordProtocol: "_tcp",
                port: 5222,
                weight: 1
            ),
        ]

        let sets = goDaddyRecordSets(from: records)
        let mx = sets.first { $0.type == "MX" }
        let sip = sets.first { $0.service == "_sip" }

        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(mx?.snapshot().values, ["10 mx1.example.", "20 mx2.example."])
        XCTAssertNil(mx?.snapshot().priority)
        XCTAssertEqual(sip?.displayName, "_sip._tcp")
        XCTAssertEqual(sip?.snapshot().values, ["5 443 sip.example."])
        XCTAssertEqual(sip?.snapshot().priority, 10)
        XCTAssertNotNil(sip?.snapshot().providerData)
    }

    func testMappingNormalizesTTLAndStructuredSRVFields() throws {
        let mutation = try CreateProviderRecordRequest(
            name: "_sip._tcp.voice.example.com",
            type: "SRV",
            content: "5 443 sip.example.net.",
            ttl: 60,
            proxied: nil,
            priority: 10,
            comment: nil
        ).toGoDaddyMutation(zoneName: "example.com")

        XCTAssertEqual(mutation.nativeName, "voice")
        XCTAssertEqual(mutation.service, "_sip")
        XCTAssertEqual(mutation.recordProtocol, "_tcp")
        XCTAssertEqual(mutation.records[0].ttl, 600)
        XCTAssertEqual(mutation.records[0].priority, 10)
        XCTAssertEqual(mutation.records[0].weight, 5)
        XCTAssertEqual(mutation.records[0].port, 443)
        XCTAssertEqual(mutation.records[0].data, "sip.example.net.")
    }

    func testSRVUpdatePreservesSiblingServiceRecords() async throws {
        let current = [
            Self.record(
                type: "SRV",
                name: "@",
                data: "old.example.",
                priority: 10,
                service: "_sip",
                recordProtocol: "_tcp",
                port: 443,
                weight: 5
            ),
            Self.record(
                type: "SRV",
                name: "@",
                data: "xmpp.example.",
                priority: 20,
                service: "_xmpp",
                recordProtocol: "_tcp",
                port: 5222,
                weight: 1
            ),
        ]
        let transport = GoDaddyRecordingTransport { request, index in
            XCTAssertEqual(request.url?.path, "/v1/domains/example.com/records/SRV/@")
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "GET")
                return try Self.response(request: request, status: 200, data: JSONEncoder().encode(current))
            }
            XCTAssertEqual(request.httpMethod, "PUT")
            let body = try JSONDecoder().decode([GoDaddyWriteRecord].self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body.count, 2)
            XCTAssertEqual(body.first(where: { $0.service == "_sip" })?.data, "new.example.")
            XCTAssertEqual(body.first(where: { $0.service == "_xmpp" })?.data, "xmpp.example.")
            return try Self.response(request: request, status: 200, body: "")
        }
        let adapter = GoDaddyDNSProviderService(service: makeService(transport: transport))
        let zone = providerZone()
        let sip = try XCTUnwrap(goDaddyRecordSets(from: current).first(where: { $0.service == "_sip" }))
        let record = ProviderRecord(provider: .goDaddy, snapshot: sip.snapshot())

        try await adapter.updateRecord(
            in: zone,
            record: record,
            edits: UpdateProviderRecordRequest(content: "5 443 new.example.")
        )

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRenameRollsBackDestinationWhenOldSetDeletionFails() async throws {
        let old = Self.record(name: "www", data: "192.0.2.1")
        let transport = GoDaddyRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/domains/example.com/records/A/api")
                return try Self.response(request: request, status: 200, body: "[]")
            case 1:
                XCTAssertEqual(request.httpMethod, "PATCH")
                return try Self.response(request: request, status: 200, body: "")
            case 2:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v1/domains/example.com/records/A/www")
                return try Self.response(
                    request: request,
                    status: 500,
                    body: #"{"code":"SERVER_ERROR","message":"temporary failure"}"#
                )
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v1/domains/example.com/records/A/api")
                return try Self.response(request: request, status: 204, body: "")
            }
        }
        let adapter = GoDaddyDNSProviderService(service: makeService(transport: transport))
        let set = try XCTUnwrap(goDaddyRecordSets(from: [old]).first)

        do {
            try await adapter.updateRecord(
                in: providerZone(),
                record: ProviderRecord(provider: .goDaddy, snapshot: set.snapshot()),
                edits: UpdateProviderRecordRequest(name: "api")
            )
            XCTFail("Expected old-set deletion to fail")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .goDaddy)
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(message, "temporary failure")
        }
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testRegistrarManagedNSIsRejectedBeforeNetwork() async throws {
        let transport = GoDaddyRecordingTransport { _, _ in
            XCTFail("Registrar-managed records should not reach the network")
            throw URLError(.badServerResponse)
        }
        let adapter = GoDaddyDNSProviderService(service: makeService(transport: transport))
        let ns = Self.record(type: "NS", name: "@", data: "ns1.domaincontrol.com")
        let set = try XCTUnwrap(goDaddyRecordSets(from: [ns]).first)

        do {
            try await adapter.deleteRecord(
                in: providerZone(),
                record: ProviderRecord(provider: .goDaddy, snapshot: set.snapshot())
            )
            XCTFail("Expected a read-only record error")
        } catch let ProviderOperationError.readOnlyRecord(provider, _) {
            XCTAssertEqual(provider, .goDaddy)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testValidationFieldsRemainVisibleInAPIError() async throws {
        let transport = GoDaddyRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 422,
                body: #"{"code":"INVALID_BODY","message":"Request validation failed","fields":[{"code":"INVALID_VALUE","message":"must be at least 600","path":"records[0].ttl"}]}"#
            )
        }

        do {
            try await makeService(transport: transport).deleteRecordSet(
                domain: "example.com",
                type: "A",
                name: "www"
            )
            XCTFail("Expected API validation error")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .goDaddy)
            XCTAssertEqual(statusCode, 422)
            XCTAssertEqual(message, "Request validation failed\nrecords[0].ttl: must be at least 600")
        }
    }

    private func makeService(transport: GoDaddyRecordingTransport) -> GoDaddyService {
        GoDaddyService(
            credentialsProvider: { (token: "unit-token", shopperId: "shopper-42") },
            baseURL: URL(string: "https://api.godaddy.test")!,
            transport: transport,
            sleep: { _ in }
        )
    }

    private func providerZone() -> ProviderZone {
        let domain = GoDaddyDomain(
            domain: "example.com",
            domainId: 42,
            status: "ACTIVE",
            nameServers: ["ns1.domaincontrol.com", "ns2.domaincontrol.com"],
            createdAt: nil
        )
        return ProviderZone(provider: .goDaddy, snapshot: domain.snapshot(), environmentId: UUID())
    }

    private static func record(
        type: String = "A",
        name: String,
        data: String,
        ttl: Int = 3600,
        priority: Int? = nil,
        service: String? = nil,
        recordProtocol: String? = nil,
        port: Int? = nil,
        weight: Int? = nil
    ) -> GoDaddyDNSRecord {
        GoDaddyDNSRecord(
            type: type,
            name: name,
            data: data,
            ttl: ttl,
            priority: priority,
            service: service,
            recordProtocol: recordProtocol,
            port: port,
            weight: weight
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

@MainActor
private final class GoDaddyRecordingTransport: NetworkTransport {
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
