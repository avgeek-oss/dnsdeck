import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class ProviderFoundationTests: XCTestCase {
    func testProviderRegistryDispatchesThroughTypeErasedService() async throws {
        let environmentId = UUID()
        let expectedZone = ProviderZone(
            provider: .cloudflare,
            snapshot: ProviderZoneSnapshot(id: "zone-1", name: "example.com"),
            environmentId: environmentId
        )
        let service = FoundationMockProviderService(zones: [expectedZone])
        let registry = ProviderServiceRegistry([service])

        let zones = try await DNSProvider.cloudflare.listZones(
            environmentId: environmentId,
            services: registry
        )

        XCTAssertEqual(zones, [expectedZone])
        XCTAssertEqual(service.listZonesCallCount, 1)
    }

    func testProviderRegistryRejectsMissingService() {
        let registry = ProviderServiceRegistry([])

        XCTAssertThrowsError(try registry.service(for: .route53)) { error in
            guard case ProviderOperationError.missingService(.route53) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCloudflareListZonesPaginatesAndAuthenticates() async throws {
        let transport = RecordingNetworkTransport { request, index in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-value")
            XCTAssertEqual(request.url?.path, "/client/v4/zones")

            let page = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first(where: { $0.name == "page" })?.value
            let body = if page == "1" {
                """
                {"success":true,"errors":[],"result":[{"id":"z1","name":"one.example","status":"active"}],"result_info":{"page":1,"total_pages":2}}
                """
            } else {
                """
                {"success":true,"errors":[],"result":[{"id":"z2","name":"two.example","status":"active"}],"result_info":{"page":2,"total_pages":2}}
                """
            }
            return try Self.response(request: request, status: 200, body: body, requestIndex: index)
        }
        let service = CloudflareService(tokenProvider: { "token-value" }, transport: transport)

        let zones = try await service.listZones()

        XCTAssertEqual(zones.map(\.id), ["z1", "z2"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRoute53CreateHostedZoneUsesDocumentedXMLAndSigV4() async throws {
        let fixedDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2015-08-30T12:36:00Z")
        )
        let transport = RecordingNetworkTransport { request, index in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/2013-04-01/hostedzone")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Amz-Date"), "20150830T123600Z")
            XCTAssertTrue(
                request.value(forHTTPHeaderField: "Authorization")?
                    .hasPrefix("AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/route53/aws4_request") ==
                    true
            )
            XCTAssertFalse(request.value(forHTTPHeaderField: "Authorization")?.contains("SECRET") == true)

            let requestBody = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
            XCTAssertTrue(requestBody.contains("<CreateHostedZoneRequest"))
            XCTAssertTrue(requestBody.contains("<Name>example.com</Name>"))
            XCTAssertTrue(requestBody.contains("<PrivateZone>false</PrivateZone>"))

            let body = """
            <?xml version="1.0" encoding="UTF-8"?>
            <CreateHostedZoneResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <HostedZone>
                <Id>/hostedzone/Z1PA6795UKMFR9</Id>
                <Name>example.com.</Name>
                <CallerReference>dnsdeck-reference</CallerReference>
                <Config><Comment>Created via DNSDeck</Comment><PrivateZone>false</PrivateZone></Config>
                <ResourceRecordSetCount>2</ResourceRecordSetCount>
              </HostedZone>
              <ChangeInfo><Id>/change/C1</Id><Status>PENDING</Status><SubmittedAt>2015-08-30T12:36:00Z</SubmittedAt></ChangeInfo>
              <DelegationSet><NameServers><NameServer>ns-1.example.net</NameServer><NameServer>ns-2.example.net</NameServer></NameServers></DelegationSet>
            </CreateHostedZoneResponse>
            """
            return try Self.response(request: request, status: 201, body: body, requestIndex: index)
        }
        let service = Route53Service(
            credentialsProvider: { ("AKIDEXAMPLE", "SECRET") },
            transport: transport,
            dateProvider: { fixedDate }
        )

        let zone = try await service.createHostedZone(name: "example.com")

        XCTAssertEqual(zone.id, "/hostedzone/Z1PA6795UKMFR9")
        XCTAssertEqual(zone.name, "example.com.")
        XCTAssertEqual(zone.nameServers, ["ns-1.example.net", "ns-2.example.net"])
    }

    func testRoute53ListRecordsPreservesAliasAndRoutingFields() async throws {
        let transport = RecordingNetworkTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/2013-04-01/hostedzone/Z1/rrset")
            let body = """
            <ListResourceRecordSetsResponse xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
              <ResourceRecordSets>
                <ResourceRecordSet>
                  <Name>weighted.example.com.</Name><Type>A</Type><SetIdentifier>west</SetIdentifier>
                  <Weight>25</Weight><Region>us-west-2</Region><Failover>PRIMARY</Failover>
                  <GeoLocation><CountryCode>US</CountryCode><SubdivisionCode>CA</SubdivisionCode></GeoLocation>
                  <MultiValueAnswer>true</MultiValueAnswer><HealthCheckId>health-1</HealthCheckId>
                  <AliasTarget>
                    <HostedZoneId>ZALIAS</HostedZoneId><DNSName>target.example.com.</DNSName>
                    <EvaluateTargetHealth>true</EvaluateTargetHealth>
                  </AliasTarget>
                </ResourceRecordSet>
              </ResourceRecordSets>
              <IsTruncated>false</IsTruncated>
            </ListResourceRecordSetsResponse>
            """
            return try Self.response(request: request, status: 200, body: body, requestIndex: index)
        }
        let service = Route53Service(
            credentialsProvider: { ("AKIDEXAMPLE", "SECRET") },
            transport: transport
        )

        let records = try await service.listResourceRecordSets(hostedZoneId: "/hostedzone/Z1")
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.aliasTarget?.dnsName, "target.example.com.")
        XCTAssertEqual(record.aliasTarget?.hostedZoneId, "ZALIAS")
        XCTAssertEqual(record.aliasTarget?.evaluateTargetHealth, true)
        XCTAssertEqual(record.setIdentifier, "west")
        XCTAssertEqual(record.weight, 25)
        XCTAssertEqual(record.region, "us-west-2")
        XCTAssertEqual(record.geoLocation?.countryCode, "US")
        XCTAssertEqual(record.geoLocation?.subdivisionCode, "CA")
        XCTAssertEqual(record.failover, "PRIMARY")
        XCTAssertEqual(record.multiValueAnswer, true)
        XCTAssertEqual(record.healthCheckId, "health-1")
    }

    func testVercelCreateDomainUsesPersonalOrTeamScope() async throws {
        let transport = RecordingNetworkTransport { request, index in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v4/domains")
            XCTAssertEqual(request.url?.query, "teamId=team_123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-value")

            let json = try XCTUnwrap(request.httpBody)
            XCTAssertEqual(try JSONDecoder().decode(VercelCreateDomainRequest.self, from: json).name, "example.com")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"uid":"domain_1","name":"example.com","nameservers":["ns1.vercel-dns.com"]}"#,
                requestIndex: index
            )
        }
        let service = VercelService(
            tokenProvider: { "token-value" },
            teamIdProvider: { "team_123" },
            transport: transport
        )

        let domain = try await service.createDomain(name: "example.com")

        XCTAssertEqual(domain.id, "domain_1")
        XCTAssertEqual(domain.nameservers, ["ns1.vercel-dns.com"])
    }

    func testGoogleCloudCreateZoneUsesManagedZonesContract() async throws {
        let transport = RecordingNetworkTransport { request, index in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/dns/v1/projects/project-123/managedZones")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")

            let body = try JSONDecoder().decode(
                GCPCreateManagedZoneRequest.self,
                from: XCTUnwrap(request.httpBody)
            )
            XCTAssertEqual(body.name, "example-com")
            XCTAssertEqual(body.dnsName, "example.com.")
            XCTAssertEqual(body.visibility, "public")

            return try Self.response(
                request: request,
                status: 201,
                body: #"{"id":"123","name":"example-com","dnsName":"example.com.","description":"Created via DNSDeck","visibility":"public","nameServers":["ns-cloud.example"]}"#,
                requestIndex: index
            )
        }
        let service = GoogleCloudService(
            credentialsProvider: { nil },
            projectIdProvider: { "project-123" },
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        let zone = try await service.createZone(name: "example.com")

        XCTAssertEqual(zone.id, "123")
        XCTAssertEqual(zone.dnsName, "example.com.")
        XCTAssertEqual(zone.nameServers, ["ns-cloud.example"])
    }

    func testGoogleCloudCreateZoneTrimsHyphenAfterResourceNameTruncation() async throws {
        let longLabel = String(repeating: "a", count: 62)
        let domain = "\(longLabel).com"
        let transport = RecordingNetworkTransport { request, index in
            let body = try JSONDecoder().decode(
                GCPCreateManagedZoneRequest.self,
                from: XCTUnwrap(request.httpBody)
            )
            XCTAssertEqual(body.name, longLabel)

            return try Self.response(
                request: request,
                status: 201,
                body: #"{"id":"123","name":"fixture","dnsName":"fixture.","description":"Created via DNSDeck","visibility":"public"}"#,
                requestIndex: index
            )
        }
        let service = GoogleCloudService(
            credentialsProvider: { nil },
            projectIdProvider: { "project-123" },
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        _ = try await service.createZone(name: domain)
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String,
        requestIndex _: Int
    ) throws -> (Data, URLResponse) {
        let response = try XCTUnwrap(
            try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (Data(body.utf8), response)
    }
}

@MainActor
private final class RecordingNetworkTransport: NetworkTransport {
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

@MainActor
private final class FoundationMockProviderService: DNSProviderService {
    let provider = DNSProvider.cloudflare
    let zones: [ProviderZone]
    private(set) var listZonesCallCount = 0

    init(zones: [ProviderZone]) {
        self.zones = zones
    }

    func listZones(environmentId _: UUID) async throws -> [ProviderZone] {
        listZonesCallCount += 1
        return zones
    }

    func records(for _: ProviderZone) async throws -> [ProviderRecord] {
        []
    }

    func createRecord(in _: ProviderZone, payload _: CreateProviderRecordRequest) async throws {}
    func deleteRecord(in _: ProviderZone, record _: ProviderRecord) async throws {}
    func updateRecord(
        in _: ProviderZone,
        record _: ProviderRecord,
        edits _: UpdateProviderRecordRequest
    ) async throws {}
}
