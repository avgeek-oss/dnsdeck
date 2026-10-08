import Security
import XCTest
@testable import DNSDeckMCP

@MainActor
final class GoogleCloudProviderTests: XCTestCase {
    func testOAuthSignsVerifiableJWTAndCachesAccessToken() async throws {
        let (pem, key) = try Self.ephemeralKey()
        let credentials = try Self.credentials(pem)
        let transport = StubTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.url?.host, "oauth2.googleapis.com")
                XCTAssertEqual(request.httpMethod, "POST")
                let form = try StubTransport.formBody(request)
                XCTAssertEqual(form["grant_type"], "urn:ietf:params:oauth:grant-type:jwt-bearer")
                let jwt = try XCTUnwrap(form["assertion"]).split(separator: ".").map(String.init)
                XCTAssertEqual(jwt.count, 3)
                let claims = try XCTUnwrap(JSONSerialization
                    .jsonObject(with: Self.decodeBase64URL(jwt[1])) as? [String: Any])
                XCTAssertEqual(claims["iss"] as? String, "unit@example.iam.gserviceaccount.com")
                XCTAssertEqual(claims["aud"] as? String, "https://oauth2.googleapis.com/token")
                XCTAssertEqual((claims["exp"] as? Int ?? 0) - (claims["iat"] as? Int ?? 0), 3600)
                let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
                XCTAssertTrue(try SecKeyVerifySignature(
                    publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                    Data("\(jwt[0]).\(jwt[1])".utf8) as CFData,
                    Self.decodeBase64URL(jwt[2]) as CFData, nil
                ))
                return try StubTransport.response(request, #"{"access_token":"ephemeral-token","expires_in":3600}"#)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ephemeral-token")
            return try StubTransport.response(request, #"{"managedZones":[]}"#)
        }
        let client = GoogleCloudService(
            credentialsProvider: { credentials },
            projectIdProvider: { "project" },
            transport: transport
        )
        _ = try await client.listZones()
        _ = try await client.listZones()
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testMalformedPrivateKeyFailsWithoutNetworkOrCrash() async throws {
        let transport = StubTransport(limit: 0) { _, _ in throw URLError(.badURL) }
        let malformedKeys = [
            Data(),
            Data(repeating: 0, count: 28),
            Data([0x30, 0x7F, 0x02, 0x7F] + Array(repeating: 0, count: 28)),
            Data([0x30, 0xFF] + Array(repeating: 0, count: 28)),
            Data([0x30, 0x1B, 0x02, 0x01, 0x00, 0x30, 0x7F] + Array(repeating: 0, count: 24)),
        ]
        for bytes in malformedKeys {
            let credentials = try Self.credentials(bytes.base64EncodedString())
            let client = GoogleCloudService(
                credentialsProvider: { credentials },
                projectIdProvider: { "project" },
                transport: transport
            )
            do {
                _ = try await client.listZones()
                XCTFail("Expected malformed key rejection")
            } catch GCPAPIError.jwt {}
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testZonesPaginateAuthenticateAndFilterAfterAllPages() async throws {
        let transport = StubTransport { request, index in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-access")
            XCTAssertEqual(request.url?.path, "/dns/v1/projects/unit-project/managedZones")
            XCTAssertEqual(request.url?.query?.contains("pageToken=next"), index == 1)
            return try StubTransport.response(request, """
            {"managedZones":[{"id":"\(index)","name":"zone\(index)","dnsName":"\(index == 0 ? "one" : "two").example.com."}]\(index == 0 ? ",\"nextPageToken\":\"next\"" : "")}
            """)
        }
        let zones = try await service(transport).listZones(nameFilter: "TWO.EXAMPLE")
        XCTAssertEqual(zones.map(\.name), ["zone1"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRecordPaginationPreservesEveryValueAndTTL() async throws {
        let transport = StubTransport { request, index in
            XCTAssertEqual(request.url?.path, "/dns/v1/projects/unit-project/managedZones/z1/rrsets")
            XCTAssertEqual(request.url?.query?.contains("pageToken=next"), index == 1)
            return try StubTransport.response(request, """
            {"rrsets":[{"name":"www\(index).example.com.","type":"A","ttl":300,"rrdatas":["192.0.2.1","192.0.2.2"]}]\(index == 0 ? ",\"nextPageToken\":\"next\"" : "")}
            """)
        }
        let records = try await service(transport).listRecords(zoneId: "z1")
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].snapshot().values, ["192.0.2.1", "192.0.2.2"])
        XCTAssertEqual(records[1].ttl, 300)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testCRUDUsesChangesEndpointAndExactOldRRSetForAtomicUpdate() async throws {
        let old = GCPResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            rrdatas: ["192.0.2.1", "192.0.2.2"]
        )
        let new = GCPResourceRecordSet(name: "www.example.com.", type: "A", ttl: 600, rrdatas: ["192.0.2.3"])
        let transport = StubTransport { request, index in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/dns/v1/projects/unit-project/managedZones/z1/changes")
            let body = try StubTransport.jsonBody(request)
            let additions = body["additions"] as? [[String: Any]]
            let deletions = body["deletions"] as? [[String: Any]]
            XCTAssertEqual(
                additions?.first?["rrdatas"] as? [String],
                index == 0 ? old.rrdatas : index == 1 ? new.rrdatas : nil
            )
            XCTAssertEqual(deletions?.first?["rrdatas"] as? [String], index == 0 ? nil : old.rrdatas)
            if index != 0 { XCTAssertEqual(deletions?.first?["ttl"] as? Int, 300) }
            return try StubTransport.response(request, #"{"status":"pending","id":"change-1"}"#)
        }
        let client = service(transport)
        _ = try await client.createRecord(zoneId: "z1", record: old)
        _ = try await client.updateRecord(zoneId: "z1", oldRecord: old, newRecord: new)
        try await client.deleteRecord(zoneId: "z1", record: old)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testMixedMXPrioritiesAndTXTQuotesSurviveTTLOnlyEdits() {
        let mx = GCPResourceRecordSet(
            name: "example.com.",
            type: "MX",
            ttl: 300,
            rrdatas: ["10 one.example.com.", "20 two.example.com."]
        )
        let txt = GCPResourceRecordSet(
            name: "example.com.",
            type: "TXT",
            ttl: 300,
            rrdatas: ["\"hello \" \"world\"", "\"second\""]
        )
        for record in [mx, txt] {
            let updated = UpdateProviderRecordRequest(ttl: 600).toGoogleCloudRequest(
                oldRecord: record,
                zoneName: "example.com."
            )
            XCTAssertEqual(updated.rrdatas, record.rrdatas)
            XCTAssertEqual(updated.ttl, 600)
        }
    }

    func testPermissionErrorAndMalformedJSONSurfaceWithoutRetry() async throws {
        for status in [403, 200] {
            let transport = StubTransport(limit: 1) { request, _ in
                try StubTransport.response(
                    request,
                    status == 403 ? #"{"error":{"code":403,"message":"Denied"}}"# : "{",
                    status: status
                )
            }
            do {
                _ = try await service(transport).listZones()
                XCTFail("Expected provider failure")
            } catch let error as GCPAPIError {
                if status == 403 { XCTAssertTrue(error.localizedDescription.contains("Denied")) }
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testMissingProjectAndInvalidCredentialsDoNotSend() async throws {
        let transport = StubTransport(limit: 0) { _, _ in throw URLError(.badURL) }
        let clients = [
            GoogleCloudService(credentialsProvider: { nil }, projectIdProvider: { nil }, transport: transport),
            GoogleCloudService(credentialsProvider: { nil }, projectIdProvider: { "project" }, transport: transport),
            GoogleCloudService(credentialsProvider: { "{}" }, projectIdProvider: { "project" }, transport: transport),
        ]
        for client in clients {
            do {
                _ = try await client.listZones()
                XCTFail("Expected invalid configuration")
            } catch is GCPAPIError {}
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func service(_ transport: StubTransport) -> GoogleCloudService {
        GoogleCloudService(
            credentialsProvider: { nil },
            projectIdProvider: { "unit-project" },
            transport: transport,
            accessTokenProvider: { "unit-access" }
        )
    }

    private static func credentials(_ pem: String) throws -> String {
        let value = GCPServiceAccount(
            project_id: "project",
            private_key: pem,
            client_email: "unit@example.iam.gserviceaccount.com",
            token_uri: "https://oauth2.googleapis.com/token"
        )
        return try String(decoding: JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func decodeBase64URL(_ value: String) throws -> Data {
        let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return try XCTUnwrap(Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)))
    }

    private static func ephemeralKey() throws -> (String, SecKey) {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        let key = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let pkcs1 = try XCTUnwrap(SecKeyCopyExternalRepresentation(key, nil)) as Data
        let algorithm = Data([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
        let pkcs8 = der(0x30, Data([0x02, 0x01, 0x00]) + algorithm + der(0x04, pkcs1))
        return ("-----BEGIN PRIVATE KEY-----\n\(pkcs8.base64EncodedString())\n-----END PRIVATE KEY-----", key)
    }

    private static func der(_ tag: UInt8, _ data: Data) -> Data {
        if data.count < 128 { return Data([tag, UInt8(data.count)]) + data }
        var length = data.count
        var bytes: [UInt8] = []
        while length > 0 {
            bytes.insert(UInt8(length & 0xFF), at: 0)
            length >>= 8
        }
        return Data([tag, 0x80 | UInt8(bytes.count)] + bytes) + data
    }
}
