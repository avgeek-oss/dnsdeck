import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class NameserverUpdateTests: XCTestCase {
    private let expectedNameservers = ["ns1.example.net", "ns2.example.net"]

    func testNormalizationTrimsLowercasesAndRemovesTrailingDot() throws {
        XCTAssertEqual(
            try NameserverUpdate.normalize([" NS1.Example.NET. ", "ns2.example.net"]),
            expectedNameservers
        )
        XCTAssertThrowsError(try NameserverUpdate.normalize(["ns1.example.net", "NS1.EXAMPLE.NET."]))
        XCTAssertThrowsError(try NameserverUpdate.normalize(["localhost", "ns2.example.net"]))
        XCTAssertThrowsError(try NameserverUpdate.normalize(["192.0.2.1", "ns2.example.net"]))
        XCTAssertThrowsError(try NameserverUpdate.normalize([".ns1.example.net", "ns2.example.net"]))
    }

    func testOnlyRegistrarCapableProvidersDeclareNameserverUpdates() {
        let providers = Set(DNSProvider.allCases.filter {
            $0.capabilities.zoneCapabilities.contains(.updateNameservers)
        })
        XCTAssertEqual(
            providers,
            [
                .dnsimple,
                .goDaddy,
                .porkbun,
                .nameCom,
                .namecheap,
                .spaceship,
                .scaleway,
                .ovhCloud,
                .route53,
                .vercel,
                .googleCloud,
            ]
        )
    }

    func testScalewayOnlyExposesNameserverUpdatesForRootZones() {
        let environmentId = UUID()
        let rootZone = ProviderZone(
            provider: .scaleway,
            snapshot: ProviderZoneSnapshot(
                id: "example.com",
                name: "example.com",
                metadata: ["domain": "example.com"]
            ),
            environmentId: environmentId
        )
        let subzone = ProviderZone(
            provider: .scaleway,
            snapshot: ProviderZoneSnapshot(
                id: "delegated.example.com",
                name: "delegated.example.com",
                metadata: ["domain": "example.com"]
            ),
            environmentId: environmentId
        )

        XCTAssertTrue(DNSProvider.scaleway.supportsNameserverUpdate(for: rootZone))
        XCTAssertFalse(DNSProvider.scaleway.supportsNameserverUpdate(for: subzone))
    }

    func testDNSimpleDelegationRequest() async throws {
        let transport = recordingTransport()
        let service = DNSimpleService(
            accountIdProvider: { "1010" },
            tokenProvider: { "token" },
            transport: transport
        )

        try await service.updateNameservers(domain: "example.com", nameservers: expectedNameservers)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/v2/1010/registrar/domains/example.com/delegation")
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: XCTUnwrap(request.httpBody)), expectedNameservers)
    }

    func testGoDaddyDomainPatch() async throws {
        let transport = recordingTransport()
        let service = GoDaddyService(
            credentialsProvider: { (token: "key:secret", shopperId: nil) },
            transport: transport
        )

        try await service.updateNameservers(domain: "example.com", nameservers: expectedNameservers)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/v1/domains/example.com")
        XCTAssertEqual(
            try JSONDecoder().decode(GoDaddyNameserverUpdateRequest.self, from: XCTUnwrap(request.httpBody)),
            GoDaddyNameserverUpdateRequest(nameServers: expectedNameservers)
        )
    }

    func testPorkbunRegistryRequest() async throws {
        let transport = recordingTransport(body: #"{"status":"SUCCESS"}"#)
        let service = PorkbunService(
            credentialsProvider: { (apiKey: "key", secretApiKey: "secret") },
            transport: transport
        )

        try await service.updateNameservers(domain: "example.com", nameservers: expectedNameservers)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/json/v3/domain/updateNs/example.com")
        let body = try JSONDecoder().decode(PorkbunNameserverUpdateRequest.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.nameservers, expectedNameservers)
    }

    func testNameComSetNameserversRequest() async throws {
        let transport = recordingTransport()
        let service = NameComService(
            credentialsProvider: { (username: "user", token: "token") },
            transport: transport
        )

        try await service.updateNameservers(domain: "example.com", nameservers: expectedNameservers)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/core/v1/domains/example.com:setNameservers")
        XCTAssertEqual(
            try JSONDecoder().decode(NameComNameserverUpdateRequest.self, from: XCTUnwrap(request.httpBody)),
            NameComNameserverUpdateRequest(nameservers: expectedNameservers)
        )
    }

    func testSpaceshipCustomNameserverRequest() async throws {
        let transport = recordingTransport(status: 204)
        let service = SpaceshipService(
            credentialsProvider: { (apiKey: "key", apiSecret: "secret") },
            transport: transport
        )

        try await service.updateNameservers(domain: "example.com", nameservers: expectedNameservers)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v1/domains/example.com/nameservers")
        XCTAssertEqual(
            try JSONDecoder().decode(SpaceshipNameserverUpdateRequest.self, from: XCTUnwrap(request.httpBody)),
            SpaceshipNameserverUpdateRequest(provider: "custom", hosts: expectedNameservers)
        )
    }

    func testScalewayZoneNameserverRequest() async throws {
        let transport = recordingTransport()
        let service = ScalewayService(
            credentialsProvider: { (secretKey: "secret", projectId: "project") },
            transport: transport
        )

        try await service.updateNameservers(zoneName: "example.com", nameservers: expectedNameservers)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/domain/v2beta1/dns-zones/example.com/nameservers")
        let body = try JSONDecoder().decode(ScalewayNameserverUpdateRequest.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.nameservers.map(\.name), expectedNameservers)
        XCTAssertTrue(body.nameservers.allSatisfy(\.ip.isEmpty))
    }

    func testOVHCloudDomainNameserverTaskRequest() async throws {
        let transport = NameserverRecordingTransport { request, _ in
            let body = request.url?.path == "/1.0/auth/time" ? "1000" : "{}"
            return try Self.response(request: request, status: 200, body: body)
        }
        let service = OVHCloudService(
            credentialsProvider: {
                (
                    endpoint: "ovh-eu",
                    applicationKey: "app-key",
                    applicationSecret: "app-secret",
                    consumerKey: "consumer"
                )
            },
            transport: transport,
            now: { Date(timeIntervalSince1970: 1000) }
        )

        try await service.updateNameservers(domain: "example.com", nameservers: expectedNameservers)

        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/1.0/domain/example.com/nameServers/update")
        let body = try JSONDecoder().decode(OVHCloudNameserverUpdateRequest.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.nameServer.map(\.host), expectedNameservers)
    }

    func testRoute53DomainsUsesJSONProtocolAndServiceSigning() async throws {
        let transport = recordingTransport(body: #"{"OperationId":"operation-1"}"#)
        let service = Route53Service(
            credentialsProvider: { (accessKeyId: "access", secretAccessKey: "secret") },
            transport: transport,
            dateProvider: { Date(timeIntervalSince1970: 1_720_721_430) }
        )

        try await service.updateDomainNameservers(domain: "example.com", nameservers: expectedNameservers)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.host, "route53domains.us-east-1.amazonaws.com")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Amz-Target"),
            "Route53Domains_v20140515.UpdateDomainNameservers"
        )
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?
            .contains("/route53domains/aws4_request") == true)
        let body = try JSONDecoder().decode(R53UpdateDomainNameserversRequest.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.nameservers.map(\.name), expectedNameservers)
    }

    func testVercelRegistrarRequestSupportsTeamScopeAndEmptyResponse() async throws {
        let transport = recordingTransport(status: 204)
        let service = VercelService(
            tokenProvider: { "token" },
            teamIdProvider: { "team_123" },
            transport: transport
        )

        try await service.updateNameservers(domain: "example.com", nameservers: expectedNameservers)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/v1/registrar/domains/example.com/nameservers")
        XCTAssertEqual(
            try URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.query,
            "teamId=team_123"
        )
        XCTAssertEqual(
            try JSONDecoder().decode(VercelNameserverUpdateRequest.self, from: XCTUnwrap(request.httpBody)),
            VercelNameserverUpdateRequest(nameservers: expectedNameservers)
        )
    }

    func testGoogleCloudPreservesExistingDSRecords() async throws {
        let registration = #"{"dnsSettings":{"customDns":{"nameServers":["old.example"],"dsRecords":[{"keyTag":123,"algorithm":"RSASHA256","digestType":"SHA256","digest":"abcd"}]}}}"#
        let transport = NameserverRecordingTransport { request, index in
            try Self.response(
                request: request,
                status: 200,
                body: index == 0 ? registration : #"{"name":"operations/1"}"#
            )
        }
        let service = GoogleCloudService(
            credentialsProvider: { nil },
            projectIdProvider: { "project" },
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        try await service.updateDomainNameservers(domain: "example.com", nameservers: expectedNameservers)

        XCTAssertEqual(transport.requests[0].httpMethod, "GET")
        let request = transport.requests[1]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "domains.googleapis.com")
        XCTAssertEqual(
            request.url?.path,
            "/v1/projects/project/locations/global/registrations/example.com:configureDnsSettings"
        )
        let body = try JSONDecoder().decode(GCPConfigureDNSSettingsRequest.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.updateMask, "customDns.nameServers")
        XCTAssertEqual(body.dnsSettings.customDns?.nameServers, expectedNameservers)
        XCTAssertEqual(body.dnsSettings.customDns?.dsRecords?.first?.digest, "abcd")
    }

    private func recordingTransport(status: Int = 200, body: String = "{}") -> NameserverRecordingTransport {
        NameserverRecordingTransport { request, _ in
            try Self.response(request: request, status: status, body: body)
        }
    }

    private static func response(request: URLRequest, status: Int, body: String) throws -> (Data, URLResponse) {
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
private final class NameserverRecordingTransport: NetworkTransport {
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
