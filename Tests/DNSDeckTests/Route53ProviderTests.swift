import XCTest
@testable import DNSDeckMCP

@MainActor
final class Route53ProviderTests: XCTestCase {
    func testHostedZonePaginationSignsEveryRequest() async throws {
        let transport = StubTransport { request, index in
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?
                .contains("/us-east-1/route53/aws4_request") == true)
            XCTAssertEqual(request.url?.query?.contains("marker=next"), index == 1)
            return try StubTransport.response(request, """
            <ListHostedZonesResponse><HostedZones><HostedZone><Id>/hostedzone/Z\(index)</Id><Name>example\(index).com.</Name></HostedZone></HostedZones><IsTruncated>\(index == 0)</IsTruncated><NextMarker>next</NextMarker></ListHostedZonesResponse>
            """)
        }
        let zones = try await service(transport).listHostedZones()
        XCTAssertEqual(zones.map(\.id), ["/hostedzone/Z0", "/hostedzone/Z1"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRecordPaginationCarriesNameTypeAndRoutingIdentifier() async throws {
        let transport = StubTransport { request, index in
            if index == 1 {
                let query = try URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                    .queryItems ?? []
                XCTAssertTrue(query.contains(.init(name: "name", value: "weighted.example.com.")))
                XCTAssertTrue(query.contains(.init(name: "type", value: "A")))
                XCTAssertTrue(query.contains(.init(name: "identifier", value: "east")))
            }
            return try StubTransport.response(request, """
            <ListResourceRecordSetsResponse><ResourceRecordSets><ResourceRecordSet><Name>weighted.example.com.</Name><Type>A</Type><TTL>300</TTL><SetIdentifier>\(index == 0 ? "west" : "east")</SetIdentifier><Weight>50</Weight><ResourceRecords><ResourceRecord><Value>192.0.2.1</Value></ResourceRecord></ResourceRecords></ResourceRecordSet></ResourceRecordSets><IsTruncated>\(index == 0)</IsTruncated><NextRecordName>weighted.example.com.</NextRecordName><NextRecordType>A</NextRecordType><NextRecordIdentifier>east</NextRecordIdentifier></ListResourceRecordSetsResponse>
            """)
        }
        let records = try await service(transport).listResourceRecordSets(hostedZoneId: "/hostedzone/Z1")
        XCTAssertEqual(records.map(\.setIdentifier), ["west", "east"])
        XCTAssertNotEqual(records[0].id, records[1].id)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRecordCRUDUsesAtomicDeleteCreateAndEscapesXML() async throws {
        let old = CreateR53RecordRequest(
            name: "txt.example.com.",
            type: "TXT",
            ttl: 300,
            values: ["\"a & b\""],
            weight: nil,
            setIdentifier: nil
        )
        let new = CreateR53RecordRequest(
            name: "renamed.example.com.",
            type: "TXT",
            ttl: 600,
            values: ["\"new\""],
            weight: nil,
            setIdentifier: nil
        )
        let transport = StubTransport { request, index in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/2013-04-01/hostedzone/Z1/rrset")
            let body = try String(decoding: XCTUnwrap(request.httpBody), as: UTF8.self)
            XCTAssertTrue(body.contains("a &amp; b"))
            if index == 1 {
                XCTAssertTrue(body.contains("<Action>DELETE</Action>"))
                XCTAssertTrue(body.contains("<Action>CREATE</Action>"))
                XCTAssertTrue(body.contains("<Name>renamed.example.com.</Name>"))
            } else {
                XCTAssertTrue(body.contains("<Action>\(index == 0 ? "CREATE" : "DELETE")</Action>"))
            }
            return try StubTransport.response(
                request,
                "<ChangeResourceRecordSetsResponse><ChangeInfo><Id>/change/1</Id><Status>PENDING</Status></ChangeInfo></ChangeResourceRecordSetsResponse>"
            )
        }
        let client = service(transport)
        try await client.createRecord(hostedZoneId: "/hostedzone/Z1", request: old)
        try await client.updateRecord(
            hostedZoneId: "/hostedzone/Z1",
            request: .init(oldRecord: old.toResourceRecordSet(), newRecord: new.toResourceRecordSet())
        )
        try await client.deleteRecord(hostedZoneId: "/hostedzone/Z1", record: old.toResourceRecordSet())
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testHeterogeneousMXPrioritySurvivesSingleTargetEdit() {
        let old = CreateR53RecordRequest(
            name: "example.com.",
            type: "MX",
            ttl: 300,
            values: ["10 primary.example.com.", "20 backup.example.com."],
            weight: nil,
            setIdentifier: nil
        ).toResourceRecordSet()
        let edits = UpdateProviderRecordRequest(values: ["primary-edited.example.com.", "backup.example.com."])
        let request = edits.toRoute53Request(oldRecord: old, zoneName: "example.com")
        XCTAssertEqual(
            request.newRecord.resourceRecords?.map(\.value),
            ["10 primary-edited.example.com.", "20 backup.example.com."]
        )
        XCTAssertNil(old.snapshot().priority)
    }

    func testAccessDeniedIsNotRetried() async throws {
        let transport = StubTransport(limit: 1) { request, _ in
            try StubTransport.response(
                request,
                "<ErrorResponse><Error><Code>AccessDenied</Code><Message>Denied</Message></Error></ErrorResponse>",
                status: 403
            )
        }
        do {
            _ = try await service(transport).listHostedZones()
            XCTFail("Expected permission failure")
        } catch let error as R53APIError {
            XCTAssertTrue(error.localizedDescription.contains("Denied"))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testMissingCredentialsFailBeforeTransport() async throws {
        let transport = StubTransport(limit: 0) { _, _ in throw URLError(.badURL) }
        do {
            _ = try await Route53Service(credentialsProvider: { (nil, nil) }, transport: transport).listHostedZones()
            XCTFail("Expected missing credentials")
        } catch R53APIError.missingCredentials {}
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func service(_ transport: StubTransport) -> Route53Service {
        Route53Service(
            credentialsProvider: { ("UNITACCESS", "unit-secret") },
            transport: transport,
            dateProvider: { Date(timeIntervalSince1970: 0) }
        )
    }
}
