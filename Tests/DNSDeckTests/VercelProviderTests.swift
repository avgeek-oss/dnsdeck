import XCTest
@testable import DNSDeckMCP

@MainActor
final class VercelProviderTests: XCTestCase {
    func testDomainsAndRecordsFollowCursorsAndTeamScope() async throws {
        for records in [false, true] {
            let transport = StubTransport { request, index in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-token")
                XCTAssertTrue(request.url?.query?.contains("teamId=team-1") == true)
                XCTAssertEqual(request.url?.query?.contains("until=42"), index == 1)
                let item = records
                    ? "\"records\":[{\"id\":\"r\(index)\",\"name\":\"www\",\"type\":\"MX\",\"value\":\"mail.example.com\",\"mxPriority\":10}]"
                    : "\"domains\":[{\"id\":\"z\(index)\",\"name\":\"example\(index).com\"}]"
                return try StubTransport.response(
                    request,
                    "{\(item),\"pagination\":{\"count\":1,\"next\":\(index == 0 ? "42" : "null")}}"
                )
            }
            let client = service(transport)
            if records {
                let result = try await client.listDNSRecords(domain: "example.com")
                XCTAssertEqual(result.map(\.mxPriority), [10, 10])
            } else {
                let result = try await client.listDomains()
                XCTAssertEqual(result.map(\.id), ["z0", "z1"])
            }
            XCTAssertEqual(transport.requests.count, 2)
        }
    }

    func testRecordCRUDUsesVersionedRoutesAndMXPriority() async throws {
        let transport = StubTransport { request, index in
            XCTAssertEqual(request.httpMethod, ["POST", "PATCH", "DELETE"][index])
            XCTAssertEqual(
                request.url?.path,
                [
                    "/v2/domains/example.com/records",
                    "/v1/domains/records/r1",
                    "/v2/domains/example.com/records/r1",
                ][index]
            )
            if index < 2 {
                let body = try StubTransport.jsonBody(request)
                XCTAssertEqual(body["mxPriority"] as? Int, 20)
                XCTAssertNil(body["mx"])
            }
            return try StubTransport.response(request, [
                #"{"uid":"r1"}"#,
                #"{"id":"r1","type":"MX","name":"","value":"mail.example.com","mxPriority":20}"#,
                #"{"uid":"r1"}"#,
            ][index])
        }
        let client = service(transport)
        _ = try await client.createDNSRecord(
            domain: "example.com",
            payload: .init(type: "MX", name: "", value: "mail.example.com", ttl: 300, comment: nil, mxPriority: 20)
        )
        _ = try await client.updateDNSRecord(
            recordId: "r1",
            payload: .init(type: nil, name: nil, value: "mail.example.com", ttl: nil, comment: nil, mxPriority: 20)
        )
        _ = try await client.deleteDNSRecord(domain: "example.com", recordId: "r1")
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testProviderErrorAndMalformedJSONAreSurfacedWithoutRetry() async throws {
        for status in [403, 200] {
            let transport = StubTransport(limit: 1) { request, _ in
                try StubTransport.response(
                    request,
                    status == 403 ? #"{"error":{"code":"forbidden","message":"Denied"}}"# : "{",
                    status: status
                )
            }
            do {
                _ = try await service(transport).listDomains()
                XCTFail("Expected error")
            } catch let error as VercelServiceError {
                if status == 403 { XCTAssertTrue(error.localizedDescription.contains("Denied")) }
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testMissingTokenFailsBeforeTransport() async throws {
        let transport = StubTransport(limit: 0) { _, _ in throw URLError(.badURL) }
        do {
            _ = try await VercelService(tokenProvider: { nil }, transport: transport).listDomains()
            XCTFail("Expected missing credential")
        } catch VercelServiceError.missingToken {}
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func service(_ transport: StubTransport) -> VercelService {
        VercelService(tokenProvider: { "unit-token" }, teamIdProvider: { "team-1" }, transport: transport)
    }
}
