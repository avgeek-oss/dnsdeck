import XCTest
@testable import DNSDeckMCP

@MainActor
final class CloudflareProviderTests: XCTestCase {
    func testRecordPaginationAuthenticatesAndPreservesNativeData() async throws {
        let transport = StubTransport { request, index in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-token")
            XCTAssertEqual(request.url?.path, "/client/v4/zones/z1/dns_records")
            XCTAssertTrue(request.url?.query?.contains("page=\(index + 1)") == true)
            return try StubTransport.response(request, """
            {"success":true,"errors":[],"result":[{"id":"r\(index)","type":"MX","name":"example.com","content":"mail.example.com","priority":\(10 + index),"ttl":300}],"result_info":{"page":\(index + 1),"total_pages":2}}
            """)
        }
        let records = try await service(transport).listRecords(zoneId: "z1")
        XCTAssertEqual(records.map(\.priority), [10, 11])
        XCTAssertEqual(records.map(\.id), ["r0", "r1"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testCreateGetZoneUsesConfiguredAccountAndNameFilter() async throws {
        let transport = StubTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "POST")
                let body = try StubTransport.jsonBody(request)
                XCTAssertEqual((body["account"] as? [String: String])?["id"], "account-1")
                XCTAssertEqual(body["name"] as? String, "example.com")
            } else {
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/client/v4/zones/z1")
            }
            return try StubTransport.response(
                request,
                #"{"success":true,"errors":[],"result":{"id":"z1","name":"example.com"}}"#
            )
        }
        let client = service(transport)
        let zone = try await client.createZone(name: "example.com")
        let fetched = try await client.getZone(zoneId: zone.id)
        XCTAssertEqual(zone, fetched)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testCreateUpdateDeleteRecordUseDistinctMethodsAndPreserveProxyComment() async throws {
        let transport = StubTransport { request, index in
            XCTAssertEqual(request.httpMethod, ["POST", "PATCH", "DELETE"][index])
            if index < 2 {
                let body = try StubTransport.jsonBody(request)
                XCTAssertEqual(body["content"] as? String, "192.0.2.1")
                XCTAssertEqual(body["proxied"] as? Bool, true)
                XCTAssertEqual(body["comment"] as? String, "unit fixture")
            } else {
                XCTAssertNil(request.httpBody)
                return try StubTransport.response(request, #"{"success":true,"errors":[],"result":{"id":"r1"}}"#)
            }
            return try StubTransport.response(
                request,
                #"{"success":true,"errors":[],"result":{"id":"r1","name":"www.example.com","type":"A","content":"192.0.2.1"}}"#
            )
        }
        let client = service(transport)
        let create = CreateProviderRecordRequest(
            name: "www",
            type: "A",
            content: "192.0.2.1",
            ttl: 300,
            proxied: true,
            priority: nil,
            comment: "unit fixture"
        )
        let created = try await client.createRecord(
            zoneId: "z1",
            payload: create.toCloudflareRequest(zoneName: "example.com")
        )
        _ = try await client.updateRecord(
            zoneId: "z1",
            recordId: created.id,
            payload: UpdateProviderRecordRequest(content: "192.0.2.1", proxied: true, comment: "unit fixture")
                .toCloudflareRequest(zoneName: "example.com")
        )
        try await client.deleteRecord(zoneId: "z1", recordId: created.id)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testHTTPAndEnvelopeErrorsAreNotSuccessfulEmptyLists() async throws {
        for status in [200, 403] {
            let transport = StubTransport(limit: 1) { request, _ in
                try StubTransport.response(
                    request,
                    #"{"success":false,"errors":[{"code":10000,"message":"Authentication error"}],"result":null}"#,
                    status: status
                )
            }
            do {
                _ = try await service(transport).listZones()
                XCTFail("Failure envelope must not appear as an empty zone list")
            } catch let CFAPIError.cloudflare(errors) {
                XCTAssertEqual(errors.first?.code, 10000)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testMalformedJSONIsDecodingError() async throws {
        let transport = StubTransport { request, _ in try StubTransport.response(request, "{") }
        do {
            _ = try await service(transport).listRecords(zoneId: "z1")
            XCTFail("Expected decoding failure")
        } catch CFAPIError.decoding {}
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testMissingTokenFailsBeforeTransport() async throws {
        let transport = StubTransport(limit: 0) { _, _ in throw URLError(.badURL) }
        do {
            _ = try await CloudflareService(tokenProvider: { nil }, transport: transport).listZones()
            XCTFail("Expected missing credential")
        } catch CFAPIError.missingToken {}
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testStructuredRecordsEncodeDataInsteadOfFlatContent() throws {
        for (type, content, expectedKey) in [
            ("DS", "12345 13 2 ABCDEF", "key_tag"),
            ("SSHFP", "1 2 ABCDEF", "fingerprint"),
            ("TLSA", "3 1 1 ABCDEF", "certificate"),
            ("HTTPS", "1 target.example.com alpn=h2", "priority"),
        ] {
            let payload = CreateProviderRecordRequest(
                name: "www",
                type: type,
                content: content,
                ttl: 300,
                proxied: nil,
                priority: nil,
                comment: nil
            )
            let body = try XCTUnwrap(JSONSerialization
                .jsonObject(with: JSONEncoder()
                    .encode(payload.toCloudflareRequest(zoneName: "example.com"))) as? [String: Any])
            XCTAssertNil(body["content"], type)
            XCTAssertNotNil((body["data"] as? [String: Any])?[expectedKey], type)
        }
    }

    private func service(_ transport: StubTransport) -> CloudflareService {
        CloudflareService(tokenProvider: { "unit-token" }, accountIdProvider: { "account-1" }, transport: transport)
    }
}
