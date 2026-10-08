import AvgeekNetworking
import CoreFoundation
import CryptoKit
import Security
import XCTest
@testable import DNSDeckMCP

@MainActor
final class OracleCloudProviderTests: XCTestCase {
    func testSignerMatchesOCIGetCanonicalContract() throws {
        var captured = ""
        let signer = OCIRequestSigner(
            tenancyId: "ocid1.tenancy.oc1..fixture",
            userId: "ocid1.user.oc1..fixture",
            fingerprint: "aa:bb:cc",
            privateKeyPEM: "fixture-key",
            signatureProvider: { signingString, _ in
                captured = signingString
                return Data([1, 2, 3])
            }
        )
        let url = try XCTUnwrap(URL(string: "https://dns.us-ashburn-1.oci.oraclecloud.com/20180115/zones?scope=GLOBAL"))

        let headers = try signer.headers(
            method: "GET",
            url: url,
            body: nil,
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(
            captured,
            "date: Thu, 01 Jan 1970 00:00:00 GMT\n" +
                "(request-target): get /20180115/zones?scope=GLOBAL\n" +
                "host: dns.us-ashburn-1.oci.oraclecloud.com"
        )
        XCTAssertEqual(headers["Date"], "Thu, 01 Jan 1970 00:00:00 GMT")
        XCTAssertEqual(headers["Host"], "dns.us-ashburn-1.oci.oraclecloud.com")
        XCTAssertEqual(
            headers["Authorization"],
            "Signature version=\"1\",headers=\"date (request-target) host\"," +
                "keyId=\"ocid1.tenancy.oc1..fixture/ocid1.user.oc1..fixture/aa:bb:cc\"," +
                "algorithm=\"rsa-sha256\",signature=\"AQID\""
        )
    }

    func testSignerHashesBodiesAndSignsWithPKCS8RSAKey() throws {
        let body = Data(#"{"items":[]}"#.utf8)
        var captured = ""
        let fixtureSigner = OCIRequestSigner(
            tenancyId: "tenancy",
            userId: "user",
            fingerprint: "fingerprint",
            privateKeyPEM: "fixture-key",
            signatureProvider: { signingString, _ in
                captured = signingString
                return Data(repeating: 7, count: 256)
            }
        )
        let url =
            try XCTUnwrap(URL(string: "https://dns.example.test/20180115/zones/example/records/www/A?scope=GLOBAL"))
        let headers = try fixtureSigner.headers(
            method: "PUT",
            url: url,
            body: body,
            date: Date(timeIntervalSince1970: 0)
        )
        let digest = Data(SHA256.hash(data: body)).base64EncodedString()

        XCTAssertEqual(headers["Content-Length"], String(body.count))
        XCTAssertEqual(headers["Content-Type"], "application/json")
        XCTAssertEqual(headers["x-content-sha256"], digest)
        XCTAssertTrue(captured.hasSuffix(
            "content-length: \(body.count)\ncontent-type: application/json\nx-content-sha256: \(digest)"
        ))

        let realSigner = try OCIRequestSigner(
            tenancyId: "tenancy",
            userId: "user",
            fingerprint: "fingerprint",
            privateKeyPEM: Self.generatedPKCS8PEM()
        )
        let realHeaders = try realSigner.headers(
            method: "GET",
            url: url,
            body: nil,
            date: Date(timeIntervalSince1970: 0)
        )
        let authorization = try XCTUnwrap(realHeaders["Authorization"])
        let encodedSignature = try XCTUnwrap(
            authorization.components(separatedBy: "signature=\"").last?.dropLast()
        )
        XCTAssertEqual(Data(base64Encoded: String(encodedSignature))?.count, 256)
    }

    func testEndpointSupportsOCIRealmsAndRejectsHostInjection() throws {
        XCTAssertEqual(
            try OracleCloudDNSService.endpoint(region: "us-ashburn-1").absoluteString,
            "https://dns.us-ashburn-1.oci.oraclecloud.com"
        )
        XCTAssertEqual(
            try OracleCloudDNSService.endpoint(region: "us-gov-ashburn-1", realmDomain: "oraclegovcloud.com")
                .absoluteString,
            "https://dns.us-gov-ashburn-1.oci.oraclegovcloud.com"
        )
        XCTAssertThrowsError(try OracleCloudDNSService.endpoint(region: "us-ashburn-1.attacker.example"))
        XCTAssertThrowsError(
            try OracleCloudDNSService.endpoint(region: "us-ashburn-1", realmDomain: "oraclecloud.com/path")
        )
    }

    func testZoneListingUsesHeaderPaginationIncludingEmptyPages() async throws {
        let transport = OracleRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/20180115/zones")
            XCTAssertEqual(Self.query(request, "compartmentId"), "ocid1.compartment.fixture")
            XCTAssertEqual(Self.query(request, "scope"), "GLOBAL")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
            switch index {
            case 0:
                XCTAssertNil(Self.query(request, "page"))
                return try Self.response(
                    request,
                    status: 200,
                    body: "[\(Self.zoneJSON(id: "zone-one", name: "one.example"))]",
                    headers: ["opc-next-page": "page-two"]
                )
            case 1:
                XCTAssertEqual(Self.query(request, "page"), "page-two")
                return try Self.response(request, status: 200, body: "[]", headers: ["opc-next-page": "page-three"])
            default:
                XCTAssertEqual(Self.query(request, "page"), "page-three")
                return try Self.response(
                    request,
                    status: 200,
                    body: "[\(Self.zoneJSON(id: "zone-three", name: "three.example"))]"
                )
            }
        }

        let zones = try await makeService(transport: transport).listZones()

        XCTAssertEqual(zones.map(\.name), ["one.example", "three.example"])
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testZoneCreationRetriesWithStableTokenAndPollsUntilActive() async throws {
        let transport = OracleRecordingTransport { request, index in
            if index < 2 {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/20180115/zones")
                XCTAssertEqual(Self.query(request, "scope"), "GLOBAL")
                let body = try JSONDecoder().decode(
                    OracleCloudCreateZoneRequest.self,
                    from: XCTUnwrap(request.httpBody)
                )
                XCTAssertEqual(body.name, "example.com")
                XCTAssertEqual(body.migrationSource, "NONE")
                if index == 0 {
                    return try Self.response(
                        request,
                        status: 429,
                        body: #"{"code":"TooManyRequests","message":"Slow down"}"#,
                        headers: ["Retry-After": "0"]
                    )
                }
                return try Self.response(request, status: 200, body: Self.zoneJSON(state: "CREATING"))
            }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/20180115/zones/ocid1.dns-zone.fixture")
            return try Self.response(
                request,
                status: 200,
                body: Self.zoneJSON(state: "ACTIVE"),
                headers: ["etag": "zone-etag"]
            )
        }

        let zone = try await makeService(transport: transport).createZone(name: "example.com.")

        let postRequests = transport.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(postRequests.count, 2)
        XCTAssertEqual(
            postRequests[0].value(forHTTPHeaderField: "opc-retry-token"),
            postRequests[1].value(forHTTPHeaderField: "opc-retry-token")
        )
        XCTAssertEqual(zone.lifecycleState, "ACTIVE")
        XCTAssertEqual(zone.etag, "zone-etag")
    }

    func testZoneDeleteRefreshesETagAndNameservers() async throws {
        let transport = OracleRecordingTransport { request, index in
            if index < 2 {
                XCTAssertEqual(request.httpMethod, "GET")
                return try Self.response(
                    request,
                    status: 200,
                    body: Self.zoneJSON(nameservers: ["ns1.p68.dns.oraclecloud.net", "ns2.p68.dns.oraclecloud.net"]),
                    headers: ["etag": "fresh-zone-etag"]
                )
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "fresh-zone-etag")
            return try Self.response(request, status: 204, body: "")
        }
        let adapter = OracleCloudDNSProviderService(service: makeService(transport: transport))

        let details = try await adapter.zoneDetails(for: providerZone())
        XCTAssertEqual(details.nameservers.count, 2)
        try await adapter.deleteZone(details)

        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "If-Match"), "fresh-zone-etag")
    }

    func testRecordListingGroupsRRsetsAndPreservesProtectionAndAliases() async throws {
        let records = [
            Self.recordJSON(
                domain: "_sip._tcp.example.com.",
                type: "SRV",
                rdata: "10 20 443 one.example.net.",
                hash: "h1",
                version: "v1"
            ),
            Self.recordJSON(
                domain: "_sip._tcp.example.com.",
                type: "SRV",
                rdata: "10 30 443 two.example.net.",
                hash: "h2",
                version: "v1"
            ),
            Self.recordJSON(domain: "edge.example.com.", type: "ALIAS", rdata: "target.example.net."),
            Self.recordJSON(domain: "example.com.", type: "SOA", rdata: "ns hostmaster 1 2 3 4 5", protected: true),
            Self.recordJSON(domain: "example.com.", type: "NS", rdata: "ns1.example.net.", protected: true),
        ]
        let transport = OracleRecordingTransport { request, _ in
            try Self.response(request, status: 200, body: "{\"items\":[\(records.joined(separator: ","))]}")
        }
        let adapter = OracleCloudDNSProviderService(service: makeService(transport: transport))

        let result = try await adapter.records(for: providerZone())

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.first(where: { $0.type == "SRV" })?.values.count, 2)
        XCTAssertEqual(result.first(where: { $0.type == "ALIAS" })?.aliasTarget?.name, "target.example.net.")
        XCTAssertFalse(try XCTUnwrap(result.first(where: { $0.type == "SOA" })).isEditable)
        XCTAssertFalse(try XCTUnwrap(result.first(where: { $0.type == "NS" })).isEditable)
        let srvSnapshot = try XCTUnwrap(result.first(where: { $0.type == "SRV" })).recordData.snapshot
        XCTAssertEqual(srvSnapshot.metadata["rrsetVersion"], "v1")
    }

    func testMappingsCoverOfficialEditableTypesAndTXTChunking() throws {
        let rawTypes = [
            "A", "AAAA", "ALIAS", "CERT", "CNAME", "DHCID", "DNAME", "DS", "IPSECKEY", "KEY", "KX",
            "LOC", "NAPTR", "NS", "NSAP", "PTR", "PX", "RP", "SPF", "SSHFP", "TLSA",
        ]
        for type in rawTypes {
            let mutation = try request(type: type, values: ["fixture-value"])
                .toOracleCloudMutation(zoneName: "example.com")
            XCTAssertEqual(mutation.type, type)
            XCTAssertEqual(mutation.domain, "www.example.com.")
            XCTAssertEqual(mutation.request.items.first?.rdata, "fixture-value")
        }

        XCTAssertEqual(
            try request(type: "CAA", values: ["0 issue letsencrypt.org"])
                .toOracleCloudMutation(zoneName: "example.com").request.items.first?.rdata,
            "0 issue letsencrypt.org"
        )
        XCTAssertEqual(
            try request(type: "MX", values: ["10 mail.example.net."])
                .toOracleCloudMutation(zoneName: "example.com").request.items.first?.rdata,
            "10 mail.example.net."
        )
        let srv = try request(
            type: "SRV",
            values: ["10 20 443 one.example.net.", "10 30 443 two.example.net."]
        ).toOracleCloudMutation(zoneName: "example.com")
        XCTAssertEqual(srv.request.items.count, 2)

        let longTXT = String(repeating: "a", count: 256)
        let txt = try request(type: "TXT", values: [longTXT]).toOracleCloudMutation(zoneName: "example.com")
        XCTAssertTrue(try XCTUnwrap(txt.request.items.first?.rdata).contains("\" \""))
        XCTAssertThrowsError(try request(type: "SOA", values: ["fixture"])
            .toOracleCloudMutation(zoneName: "example.com"))
        XCTAssertThrowsError(try request(type: "CNAME", values: ["one.example.", "two.example."])
            .toOracleCloudMutation(zoneName: "example.com"))
    }

    func testCreatePreflightsRRsetAndDoesNotOverwriteExistingData() async throws {
        let transport = OracleRecordingTransport { request, _ in
            XCTAssertEqual(request.httpMethod, "GET")
            return try Self.response(
                request,
                status: 200,
                body: "{\"items\":[\(Self.recordJSON(domain: "www.example.com.", type: "A", rdata: "192.0.2.1"))]}",
                headers: ["etag": "existing-etag"]
            )
        }
        let adapter = OracleCloudDNSProviderService(service: makeService(transport: transport))

        do {
            try await adapter.createRecord(
                in: providerZone(),
                payload: request(type: "A", values: ["192.0.2.2"])
            )
            XCTFail("Expected existing RRset conflict")
        } catch let ProviderAPIError.operationFailed(provider, operation, _) {
            XCTAssertEqual(provider, .oracleCloud)
            XCTAssertEqual(operation, "record creation")
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testUpdateRefreshesExactRRsetUsesETagAndOmitsServerFields() async throws {
        let transport = OracleRecordingTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/20180115/zones/ocid1.dns-zone.fixture/records/www.example.com./A")
                return try Self.response(
                    request,
                    status: 200,
                    body: "{\"items\":[\(Self.recordJSON(domain: "www.example.com.", type: "A", rdata: "192.0.2.1", hash: "server-hash", version: "server-version"))]}",
                    headers: ["etag": "fresh-record-etag"]
                )
            }
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "fresh-record-etag")
            XCTAssertNil(Self.query(request, "limit"))
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
            let items = body?["items"] as? [[String: Any]]
            XCTAssertEqual(items?.first?["rdata"] as? String, "192.0.2.2")
            XCTAssertNil(items?.first?["recordHash"])
            XCTAssertNil(items?.first?["rrsetVersion"])
            return try Self.response(
                request,
                status: 200,
                body: "{\"items\":[\(Self.recordJSON(domain: "www.example.com.", type: "A", rdata: "192.0.2.2"))]}",
                headers: ["etag": "updated-etag"]
            )
        }
        let adapter = OracleCloudDNSProviderService(service: makeService(transport: transport))

        try await adapter.updateRecord(
            in: providerZone(),
            record: providerRecord(),
            edits: UpdateProviderRecordRequest(content: "192.0.2.2")
        )

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testIdentityChangeRollsBackDestinationWhenSourceDeleteFails() async throws {
        let transport = OracleRecordingTransport { request, index in
            switch index {
            case 0:
                return try Self.response(
                    request,
                    status: 200,
                    body: "{\"items\":[\(Self.recordJSON(domain: "www.example.com.", type: "A", rdata: "192.0.2.1"))]}",
                    headers: ["etag": "source-etag"]
                )
            case 1:
                return try Self.response(request, status: 404, body: #"{"code":"NotFound","message":"missing"}"#)
            case 2:
                XCTAssertEqual(request.httpMethod, "PUT")
                return try Self.response(
                    request,
                    status: 200,
                    body: "{\"items\":[\(Self.recordJSON(domain: "renamed.example.com.", type: "A", rdata: "192.0.2.1"))]}",
                    headers: ["etag": "destination-etag"]
                )
            case 3:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "source-etag")
                return try Self.response(
                    request,
                    status: 412,
                    body: #"{"code":"PreconditionFailed","message":"changed"}"#
                )
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(
                    request.url?.path,
                    "/20180115/zones/ocid1.dns-zone.fixture/records/renamed.example.com./A"
                )
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "destination-etag")
                return try Self.response(request, status: 204, body: "")
            }
        }
        let adapter = OracleCloudDNSProviderService(service: makeService(transport: transport))

        do {
            try await adapter.updateRecord(
                in: providerZone(),
                record: providerRecord(),
                edits: UpdateProviderRecordRequest(name: "renamed")
            )
            XCTFail("Expected source delete failure")
        } catch let ProviderAPIError.http(provider, statusCode, _, _, _) {
            XCTAssertEqual(provider, .oracleCloud)
            XCTAssertEqual(statusCode, 412)
        }
        XCTAssertEqual(transport.requests.count, 5)
    }

    func testWritesRetry429ResponsesButNotAmbiguousTransportFailures() async throws {
        let responseTransport = OracleRecordingTransport { request, index in
            if index == 0 {
                return try Self.response(
                    request,
                    status: 429,
                    body: #"{"code":"TooManyRequests","message":"retry"}"#,
                    headers: ["Retry-After": "0"]
                )
            }
            return try Self.response(request, status: 200, body: #"{"items":[]}"#, headers: ["etag": "etag"])
        }
        _ = try await makeService(transport: responseTransport).putRRSet(
            zone: nativeZone(),
            mutation: request(type: "A", values: ["192.0.2.1"]).toOracleCloudMutation(zoneName: "example.com")
        )
        XCTAssertEqual(responseTransport.requests.count, 2)

        let failureTransport = OracleRecordingTransport { _, _ in throw URLError(.networkConnectionLost) }
        do {
            _ = try await makeService(transport: failureTransport).putRRSet(
                zone: nativeZone(),
                mutation: request(type: "A", values: ["192.0.2.1"]).toOracleCloudMutation(zoneName: "example.com")
            )
            XCTFail("Expected transport failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        }
        XCTAssertEqual(failureTransport.requests.count, 1)
    }

    func testOCIErrorSurfacesMessageAndRequestID() async throws {
        let transport = OracleRecordingTransport { request, _ in
            try Self.response(
                request,
                status: 401,
                body: #"{"code":"NotAuthenticated","message":"The required information to complete authentication was not provided."}"#,
                headers: ["opc-request-id": "request-42"]
            )
        }

        do {
            _ = try await makeService(transport: transport).listZones()
            XCTFail("Expected authentication error")
        } catch let ProviderAPIError.http(provider, statusCode, message, requestId, _) {
            XCTAssertEqual(provider, .oracleCloud)
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "The required information to complete authentication was not provided.")
            XCTAssertEqual(requestId, "request-42")
        }
    }

    func testSecondaryZonesAndProtectedRRsetsAreReadOnly() async throws {
        let adapter = OracleCloudDNSProviderService(service: makeService(transport: OracleRecordingTransport { _, _ in
            XCTFail("Read-only guards should not make a request")
            throw URLError(.badURL)
        }))
        let secondary = nativeZone(zoneType: "SECONDARY")
        let secondaryZone = ProviderZone(provider: .oracleCloud, snapshot: secondary.snapshot(), environmentId: UUID())

        do {
            try await adapter.createRecord(in: secondaryZone, payload: request(type: "A", values: ["192.0.2.1"]))
            XCTFail("Expected read-only secondary zone")
        } catch let ProviderOperationError.readOnlyZone(provider, _) {
            XCTAssertEqual(provider, .oracleCloud)
        }
    }

    private func makeService(transport: OracleRecordingTransport) -> OracleCloudDNSService {
        OracleCloudDNSService(
            credentialsProvider: Self.credentials,
            endpointURL: URL(string: "https://dns.fixture.test")!,
            transport: transport,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 0) },
            signatureProvider: { _, _ in Data(repeating: 1, count: 256) }
        )
    }

    private func nativeZone(zoneType: String = "PRIMARY") -> OracleCloudZone {
        OracleCloudZone(
            name: "example.com",
            zoneType: zoneType,
            compartmentId: "ocid1.compartment.fixture",
            scope: "GLOBAL",
            freeformTags: nil,
            definedTags: nil,
            resolutionMode: nil,
            dnssecState: nil,
            self: nil,
            id: "ocid1.dns-zone.fixture",
            timeCreated: "2026-07-10T00:00:00Z",
            version: "1",
            serial: 1,
            lifecycleState: "ACTIVE",
            isProtected: false,
            nameservers: [OracleCloudNameserver(hostname: "ns1.p68.dns.oraclecloud.net")],
            viewId: nil,
            etag: "listed-zone-etag"
        )
    }

    private func providerZone() -> ProviderZone {
        ProviderZone(provider: .oracleCloud, snapshot: nativeZone().snapshot(), environmentId: UUID())
    }

    private func providerRecord() -> ProviderRecord {
        ProviderRecord(
            provider: .oracleCloud,
            snapshot: OracleCloudRRSet(
                domain: "www.example.com.",
                type: "A",
                items: [
                    OracleCloudRecord(
                        domain: "www.example.com.",
                        recordHash: "listed-hash",
                        isProtected: false,
                        rdata: "192.0.2.1",
                        rrsetVersion: "listed-version",
                        rtype: "A",
                        ttl: 300
                    ),
                ],
                etag: nil
            ).snapshot()
        )
    }

    private func request(type: String, values: [String]) -> CreateProviderRecordRequest {
        CreateProviderRecordRequest(
            name: "www",
            type: type,
            content: values.first ?? "",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil,
            values: values
        )
    }

    private static func credentials() -> OracleCloudDNSService.Credentials {
        (
            tenancyId: "ocid1.tenancy.fixture",
            userId: "ocid1.user.fixture",
            fingerprint: "aa:bb:cc",
            privateKeyPEM: "fixture-key",
            region: "us-ashburn-1",
            compartmentId: "ocid1.compartment.fixture",
            realmDomain: nil
        )
    }

    private static func query(_ request: URLRequest, _ name: String) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    private static func zoneJSON(
        id: String = "ocid1.dns-zone.fixture",
        name: String = "example.com",
        state: String = "ACTIVE",
        zoneType: String = "PRIMARY",
        protected: Bool = false,
        nameservers: [String] = ["ns1.p68.dns.oraclecloud.net"]
    ) -> String {
        let object: [String: Any] = [
            "name": name,
            "zoneType": zoneType,
            "compartmentId": "ocid1.compartment.fixture",
            "scope": "GLOBAL",
            "id": id,
            "timeCreated": "2026-07-10T00:00:00Z",
            "version": "1",
            "serial": 1,
            "lifecycleState": state,
            "isProtected": protected,
            "nameservers": nameservers.map { ["hostname": $0] },
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func recordJSON(
        domain: String,
        type: String,
        rdata: String,
        protected: Bool = false,
        hash: String? = nil,
        version: String? = nil
    ) -> String {
        var object: [String: Any] = [
            "domain": domain,
            "rdata": rdata,
            "rtype": type,
            "ttl": 300,
            "isProtected": protected,
        ]
        if let hash { object["recordHash"] = hash }
        if let version { object["rrsetVersion"] = version }
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func response(
        _ request: URLRequest,
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

    private static func generatedPKCS8PEM() throws -> String {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
        ]
        var creationError: Unmanaged<CoreFoundation.CFError>?
        let key = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, &creationError))
        var exportError: Unmanaged<CoreFoundation.CFError>?
        let pkcs1 = try XCTUnwrap(SecKeyCopyExternalRepresentation(key, &exportError) as Data?)

        let version = Data([0x02, 0x01, 0x00])
        let rsaAlgorithmIdentifier = Data([
            0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00,
        ])
        let privateKey = der(tag: 0x04, content: pkcs1)
        let pkcs8 = der(tag: 0x30, content: version + rsaAlgorithmIdentifier + privateKey)
        let base64 = pkcs8.base64EncodedString(options: .lineLength64Characters)
        return "-----BEGIN PRIVATE KEY-----\n\(base64)\n-----END PRIVATE KEY-----"
    }

    private static func der(tag: UInt8, content: Data) -> Data {
        var result = Data([tag])
        if content.count < 128 {
            result.append(UInt8(content.count))
        } else {
            var bytes: [UInt8] = []
            var length = content.count
            while length > 0 {
                bytes.insert(UInt8(length & 0xFF), at: 0)
                length >>= 8
            }
            result.append(0x80 | UInt8(bytes.count))
            result.append(contentsOf: bytes)
        }
        result.append(content)
        return result
    }
}

@MainActor
private final class OracleRecordingTransport: NetworkTransport {
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
