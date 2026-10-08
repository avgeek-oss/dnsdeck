import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class AkamaiCloudProviderTests: XCTestCase {
    func testListDomainsPaginatesWithMaximumDocumentedPageSize() async throws {
        let transport = AkamaiCloudRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer linode-token")
            XCTAssertEqual(request.url?.path, "/v4/domains")

            if index == 0 {
                XCTAssertEqual(request.url?.query, "page=1&page_size=500")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"data":[{"id":1,"domain":"one.example","type":"master"}],"page":1,"pages":2,"results":2}"#
                )
            }
            XCTAssertEqual(request.url?.query, "page=2&page_size=500")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"data":[{"id":2,"domain":"two.example","type":"slave"}],"page":2,"pages":2,"results":2}"#
            )
        }
        let service = makeService(transport: transport)

        let domains = try await service.listDomains()

        XCTAssertEqual(domains.map(\.id), [1, 2])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testDomainCreateDetailsAndDeleteContracts() async throws {
        let transport = AkamaiCloudRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v4/domains")
                XCTAssertEqual(
                    try JSONDecoder().decode(
                        AkamaiCloudCreateDomainRequest.self,
                        from: XCTUnwrap(request.httpBody)
                    ),
                    AkamaiCloudCreateDomainRequest(
                        domain: "example.com",
                        type: "master",
                        status: "active",
                        soaEmail: "hostmaster@example.com",
                        ttlSec: 86400
                    )
                )
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"id":42,"domain":"example.com","type":"master","status":"active","soa_email":"hostmaster@example.com","ttl_sec":86400}"#
                )
            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v4/domains/42")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"id":42,"domain":"example.com","type":"master","status":"active","soa_email":"hostmaster@example.com","ttl_sec":86400}"#
                )
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v4/domains/42")
                return try Self.response(request: request, status: 200, body: "")
            }
        }
        let service = makeService(transport: transport)

        let created = try await service.createDomain(name: "example.com")
        let fetched = try await service.getDomain(id: created.id)
        try await service.deleteDomain(id: created.id)

        XCTAssertEqual(created, fetched)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testRecordSnapshotsPreserveSRVCAAAndDefaultTTLBehavior() async throws {
        let transport = AkamaiCloudRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 200,
                body: #"{"data":[{"id":1,"type":"SRV","name":"","target":"sip.example.com.","priority":10,"weight":20,"port":5060,"service":"_sip","protocol":"_tcp","ttl_sec":0,"tag":null},{"id":2,"type":"CAA","name":"","target":"letsencrypt.org","priority":0,"weight":0,"port":0,"service":null,"protocol":null,"ttl_sec":300,"tag":"issue"}],"page":1,"pages":1,"results":2}"#
            )
        }
        let service = makeService(transport: transport)

        let records = try await service.listRecords(domainId: 42)
        let srv = records[0].snapshot(defaultTTL: 86400)
        let caa = records[1].snapshot(defaultTTL: 86400)

        XCTAssertEqual(srv.name, "_sip._tcp")
        XCTAssertEqual(srv.content, "10 20 5060 sip.example.com.")
        XCTAssertEqual(srv.ttl, 86400)
        XCTAssertEqual(caa.name, "@")
        XCTAssertEqual(caa.content, "0 issue letsencrypt.org")
        XCTAssertNotNil(srv.providerData)
    }

    func testRecordCRUDUsesDocumentedMethodsAndPaths() async throws {
        let create = AkamaiCloudRecordWriteRequest(
            type: "A",
            name: "www",
            target: "192.0.2.1",
            priority: nil,
            weight: nil,
            port: nil,
            service: nil,
            protocolValue: nil,
            ttlSec: 300,
            tag: nil
        )
        let update = AkamaiCloudRecordWriteRequest(
            type: nil,
            name: "api",
            target: "192.0.2.2",
            priority: nil,
            weight: nil,
            port: nil,
            service: nil,
            protocolValue: nil,
            ttlSec: 3600,
            tag: nil
        )
        let responseRecord = #"{"id":123,"type":"A","name":"www","target":"192.0.2.1","priority":0,"weight":0,"port":0,"service":null,"protocol":null,"ttl_sec":300,"tag":null}"#
        let transport = AkamaiCloudRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v4/domains/42/records")
                XCTAssertEqual(
                    try JSONDecoder().decode(AkamaiCloudRecordWriteRequest.self, from: XCTUnwrap(request.httpBody)),
                    create
                )
                return try Self.response(request: request, status: 200, body: responseRecord)
            case 1:
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path, "/v4/domains/42/records/123")
                XCTAssertEqual(
                    try JSONDecoder().decode(AkamaiCloudRecordWriteRequest.self, from: XCTUnwrap(request.httpBody)),
                    update
                )
                return try Self.response(request: request, status: 200, body: responseRecord)
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v4/domains/42/records/123")
                return try Self.response(request: request, status: 200, body: "")
            }
        }
        let service = makeService(transport: transport)

        _ = try await service.createRecord(domainId: 42, request: create)
        _ = try await service.updateRecord(domainId: 42, recordId: 123, request: update)
        try await service.deleteRecord(domainId: 42, recordId: 123)

        XCTAssertEqual(transport.requests.count, 3)
    }

    func testRequestMappingNormalizesSRVCAAAndDiscreteTTL() throws {
        let srv = try CreateProviderRecordRequest(
            name: "_sip._tcp.example.com",
            type: "SRV",
            content: "",
            ttl: 301,
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
        ).toAkamaiCloudRequest(zoneName: "example.com")

        XCTAssertEqual(srv.type, "SRV")
        XCTAssertNil(srv.name)
        XCTAssertEqual(srv.service, "sip")
        XCTAssertEqual(srv.protocolValue, "tcp")
        XCTAssertEqual(srv.target, "sip.example.com.")
        XCTAssertEqual(srv.ttlSec, 3600)

        XCTAssertThrowsError(
            try CreateProviderRecordRequest(
                name: "@",
                type: "CAA",
                content: "",
                ttl: 300,
                proxied: nil,
                priority: nil,
                comment: nil,
                recordData: RecordData(flags: 128, tag: "issue", value: "letsencrypt.org")
            ).toAkamaiCloudRequest(zoneName: "example.com")
        )
    }

    func testUpdatePreservesNativeSRVFieldsAndOmitsType() throws {
        let existing = AkamaiCloudDomainRecord(
            id: 1,
            type: "SRV",
            name: "",
            target: "sip.example.com.",
            priority: 10,
            weight: 20,
            port: 5060,
            service: "_sip",
            protocolValue: "_tcp",
            ttlSec: 300,
            tag: nil,
            created: nil,
            updated: nil
        )

        let request = try UpdateProviderRecordRequest(ttl: 3600)
            .toAkamaiCloudRequest(zoneName: "example.com", existing: existing)

        XCTAssertNil(request.type)
        XCTAssertEqual(request.target, existing.target)
        XCTAssertEqual(request.priority, existing.priority)
        XCTAssertEqual(request.weight, existing.weight)
        XCTAssertEqual(request.port, existing.port)
        XCTAssertEqual(request.service, "sip")
        XCTAssertEqual(request.protocolValue, "tcp")
        XCTAssertEqual(request.ttlSec, 3600)

        let renamed = try UpdateProviderRecordRequest(name: "_xmpp._udp.example.com")
            .toAkamaiCloudRequest(zoneName: "example.com", existing: existing)

        XCTAssertEqual(renamed.service, "xmpp")
        XCTAssertEqual(renamed.protocolValue, "udp")
        XCTAssertEqual(renamed.target, existing.target)
        XCTAssertEqual(renamed.port, existing.port)
    }

    func testSecondaryZoneRejectsRecordMutationsBeforeNetworkRequest() async throws {
        let transport = AkamaiCloudRecordingTransport { _, _ in
            XCTFail("Read-only zone should be rejected before a request")
            throw URLError(.badServerResponse)
        }
        let adapter = AkamaiCloudDNSProviderService(service: makeService(transport: transport))
        let domain = AkamaiCloudDomain(
            id: 9,
            domain: "secondary.example",
            type: "slave",
            status: "active",
            description: nil,
            soaEmail: nil,
            retrySec: nil,
            masterIPs: ["192.0.2.1"],
            axfrIPs: [],
            tags: [],
            expireSec: nil,
            refreshSec: nil,
            ttlSec: 86400
        )
        let zone = ProviderZone(
            provider: .akamaiCloud,
            snapshot: domain.snapshot(nameservers: AkamaiCloudService.nameservers),
            environmentId: UUID()
        )

        do {
            try await adapter.createRecord(
                in: zone,
                payload: CreateProviderRecordRequest(
                    name: "www",
                    type: "A",
                    content: "192.0.2.2",
                    ttl: 300,
                    proxied: nil,
                    priority: nil,
                    comment: nil
                )
            )
            XCTFail("Expected read-only zone error")
        } catch let ProviderOperationError.readOnlyZone(provider, zoneName) {
            XCTAssertEqual(provider, .akamaiCloud)
            XCTAssertEqual(zoneName, "secondary.example")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testLinodeErrorArrayIsPresentedWithFieldContext() async throws {
        let transport = AkamaiCloudRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 400,
                body: #"{"errors":[{"field":"ttl_sec","reason":"TTL is invalid"}]}"#
            )
        }
        let service = makeService(transport: transport)

        do {
            _ = try await service.listDomains()
            XCTFail("Expected API error")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .akamaiCloud)
            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(message, "ttl_sec: TTL is invalid")
        }
    }

    private func makeService(transport: AkamaiCloudRecordingTransport) -> AkamaiCloudService {
        AkamaiCloudService(
            tokenProvider: { "linode-token" },
            baseURL: URL(string: "https://api.linode.test/v4")!,
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
                try HTTPURLResponse(
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
private final class AkamaiCloudRecordingTransport: NetworkTransport {
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
