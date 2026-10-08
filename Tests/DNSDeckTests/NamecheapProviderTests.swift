import XCTest
@testable import DNSDeckMCP

@MainActor
final class NamecheapProviderTests: XCTestCase {
    private let domain = NamecheapDomain(
        id: "1", name: "example.co.uk", sld: "example", tld: "co.uk",
        isExpired: false, isLocked: true, autoRenew: false, isOurDNS: true,
        created: nil, expires: nil, nameservers: []
    )

    func testListDomainsUsesPOSTCredentialsLongestTLDAndPagination() async throws {
        let transport = StubTransport { request, index in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://api.namecheap.com/xml.response")
            XCTAssertNil(request.url?.query)
            let form = try StubTransport.formBody(request)
            XCTAssertEqual(form["ApiKey"], "unit-key")
            XCTAssertEqual(form["ApiUser"], "unit-user")
            XCTAssertEqual(form["ClientIp"], "192.0.2.1")
            if index == 0 {
                XCTAssertEqual(form["Command"], "namecheap.domains.getTldList")
                return try self.xml(request, "<Tlds><Tld Name=\"uk\"/><Tld Name=\"co.uk\"/></Tlds>")
            }
            XCTAssertEqual(form["Page"], String(index))
            XCTAssertEqual(form["PageSize"], "100")
            return try self.xml(request, """
            <DomainGetListResult><Domain ID="\(index)" Name="site\(index).co.uk" IsOurDNS="true"/></DomainGetListResult>
            <Paging><TotalItems>2</TotalItems></Paging>
            """)
        }
        let zones = try await service(transport).listDomains()
        XCTAssertEqual(zones.map(\.tld), ["co.uk", "co.uk"])
        XCTAssertEqual(zones.map(\.sld), ["site1", "site2"])
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testDetailsAndNameserversKeepMultiLabelTLD() async throws {
        let transport = StubTransport { request, index in
            let form = try StubTransport.formBody(request)
            XCTAssertEqual(form["SLD"], "example")
            XCTAssertEqual(form["TLD"], "co.uk")
            if index == 0 {
                return try self.xml(
                    request,
                    "<DomainDNSGetListResult IsUsingOurDNS=\"true\"><Nameserver>ns1.example.net</Nameserver></DomainDNSGetListResult>"
                )
            }
            XCTAssertEqual(form["Command"], "namecheap.domains.dns.setCustom")
            XCTAssertEqual(form["NameServers"], "ns1.example.net,ns2.example.net")
            return try self.xml(request, "<DomainDNSSetCustomResult Updated=\"true\"/>")
        }
        let client = service(transport)
        let details = try await client.domainDetails(domain)
        XCTAssertEqual(details.nameservers, ["ns1.example.net"])
        try await client.updateNameservers(domain: domain, nameservers: ["ns1.example.net", "ns2.example.net"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testCreatePreservesExistingHostsAndVerifiesCompleteSet() async throws {
        let transport = StubTransport { request, index in
            switch index {
            case 0: return try self.hosts(request, [self.host()])
            case 1:
                let form = try StubTransport.formBody(request)
                XCTAssertEqual(form["Command"], "namecheap.domains.dns.setHosts")
                XCTAssertEqual(form["HostName1"], "www")
                XCTAssertEqual(form["Address1"], "192.0.2.1")
                XCTAssertEqual(form["HostName2"], "txt")
                XCTAssertEqual(form["Address2"], "hello & goodbye")
                XCTAssertNil(form["HostName3"])
                return try self.xml(request, "<DomainDNSSetHostsResult IsSuccess=\"true\"/>")
            default:
                return try self.hosts(request, [
                    self.host(),
                    self.host(id: "2", name: "txt", type: "TXT", address: "hello &amp; goodbye"),
                ])
            }
        }
        try await service(transport).createHosts(domain: domain, payload: payload("txt", "TXT", "hello & goodbye"))
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testUpdateAndDeletePreserveUnrelatedHosts() async throws {
        for deleting in [false, true] {
            let transport = StubTransport { request, index in
                if index == 0 {
                    return try self.hosts(request, [self.host(), self.host(id: "2", name: "keep")])
                }
                if index == 1 {
                    let form = try StubTransport.formBody(request)
                    XCTAssertEqual(form["HostName1"], deleting ? "keep" : "www")
                    XCTAssertEqual(form["Address1"], deleting ? "192.0.2.1" : "192.0.2.2")
                    XCTAssertEqual(form["HostName2"], deleting ? nil : "keep")
                    return try self.xml(request, "<DomainDNSSetHostsResult IsSuccess=\"true\"/>")
                }
                return try self.hosts(
                    request,
                    deleting
                        ? [self.host(id: "2", name: "keep")]
                        : [self.host(address: "192.0.2.2"), self.host(id: "2", name: "keep")]
                )
            }
            let record = NamecheapHost(
                hostId: "1",
                name: "www",
                type: "A",
                address: "192.0.2.1",
                mxPreference: nil,
                ttl: 300
            )
            if deleting {
                try await service(transport).deleteHost(domain: domain, record: record)
            } else {
                try await service(transport).updateHost(
                    domain: domain,
                    record: record,
                    edits: .init(content: "192.0.2.2")
                )
            }
            XCTAssertEqual(transport.requests.count, 3)
        }
    }

    func testBatchCreateUsesOneReplacementAndReturnsEveryResult() async throws {
        let transport = StubTransport { request, index in
            if index == 0 { return try self.hosts(request, []) }
            if index == 1 {
                let form = try StubTransport.formBody(request)
                XCTAssertEqual(form["HostName1"], "one")
                XCTAssertEqual(form["HostName2"], "two")
                return try self.xml(request, "<DomainDNSSetHostsResult IsSuccess=\"true\"/>")
            }
            return try self.hosts(request, [self.host(name: "one"), self.host(id: "2", name: "two")])
        }
        let results = await service(transport).createHosts(
            domain: domain, payloads: [payload("one"), payload("two")]
        )
        XCTAssertEqual(results.count, 2)
        for result in results {
            try result.get()
        }
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testUnsafeExistingTypesBlockFullReplacement() async throws {
        for type in ["MX", "MXE", "SRV", "UNKNOWN"] {
            let transport = StubTransport(limit: 1) { request, _ in
                try self.hosts(request, [self.host(type: type)])
            }
            do {
                try await service(transport).createHosts(domain: domain, payload: payload("new"))
                XCTFail("Must preserve unsupported \(type)")
            } catch let ProviderAPIError.operationFailed(provider, _, message) {
                XCTAssertEqual(provider, .namecheap)
                XCTAssertTrue(message?.contains(type) == true)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testMissingRecordCannotDeleteAHostSet() async throws {
        let transport = StubTransport(limit: 1) { request, _ in try self.hosts(request, []) }
        let record = NamecheapHost(
            hostId: "gone",
            name: "www",
            type: "A",
            address: "192.0.2.1",
            mxPreference: nil,
            ttl: 300
        )
        do {
            try await service(transport).deleteHost(domain: domain, record: record)
            XCTFail("Expected missing record")
        } catch let ProviderOperationError.missingRecord(recordId) {
            XCTAssertEqual(recordId, "gone")
        }
    }

    func testVerificationRejectsMissingDuplicateValuesWithBoundedRetries() async throws {
        var sleeps: [TimeInterval] = []
        let transport = StubTransport(limit: 8) { request, index in
            if index == 0 { return try self.hosts(request, [self.host()]) }
            if index == 1 { return try self.xml(request, "<DomainDNSSetHostsResult IsSuccess=\"true\"/>") }
            return try self.hosts(request, [self.host()])
        }
        do {
            try await service(transport, sleep: { sleeps.append($0) })
                .createHosts(domain: domain, payload: payload("www"))
            XCTFail("Expected duplicate-count mismatch")
        } catch let ProviderAPIError.operationFailed(_, _, message) {
            XCTAssertTrue(message?.contains("missing [1x") == true)
        }
        XCTAssertEqual(sleeps, [1, 2, 3, 4, 5])
        XCTAssertEqual(transport.requests.count, 8)
    }

    func testUnconfirmedWriteStopsBeforeVerification() async throws {
        let transport = StubTransport(limit: 2) { request, index in
            index == 0
                ? try self.hosts(request, [])
                : try self.xml(request, "<DomainDNSSetHostsResult IsSuccess=\"false\"/>")
        }
        do {
            try await service(transport).createHosts(domain: domain, payload: payload("new"))
            XCTFail("Expected unconfirmed write")
        } catch let ProviderAPIError.operationFailed(_, operation, _) {
            XCTAssertEqual(operation, "record replacement")
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testEmptyPageCannotSilentlyTruncateDomainList() async throws {
        let transport = StubTransport(limit: 2) { request, index in
            try self.xml(
                request,
                index == 0
                    ? "<Tlds><Tld Name=\"com\"/></Tlds>"
                    : "<DomainGetListResult/><Paging><TotalItems>1</TotalItems></Paging>"
            )
        }
        do {
            _ = try await service(transport).listDomains()
            XCTFail("Expected invalid pagination")
        } catch let ProviderAPIError.invalidResponse(provider) {
            XCTAssertEqual(provider, .namecheap)
        }
    }

    func testSandboxIsExplicitAndInvalidCredentialsNeverSend() async throws {
        let transport = StubTransport(limit: 1) { request, _ in
            XCTAssertEqual(request.url?.host, "api.sandbox.namecheap.com")
            return try self.xml(request, "<DomainDNSGetListResult IsUsingOurDNS=\"true\"/>")
        }
        _ = try await NamecheapService(
            credentialsProvider: { ("unit-user", "unit-key", "192.0.2.1", "sandbox") }, transport: transport
        ).domainDetails(domain)
        let invalid: [NamecheapService.Credentials] = [
            (nil, "unit-key", "192.0.2.1", nil),
            ("unit-user", " ", "192.0.2.1", nil),
            ("unit-user", "unit-key", "::1", nil),
            ("unit-user", "unit-key", "192.0.2.1", "unknown"),
        ]
        for credentials in invalid {
            do {
                _ = try await NamecheapService(credentialsProvider: { credentials }, transport: transport)
                    .domainDetails(domain)
                XCTFail("Expected credential validation")
            } catch is ProviderAPIError {}
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testXMLAndHTTPFailuresAreSurfacedWithoutRetries() async throws {
        for status in [200, 403, 503] {
            let transport = StubTransport(limit: 1) { request, _ in
                try StubTransport.response(
                    request,
                    "<ApiResponse Status=\"ERROR\"><Errors><Error Number=\"101\">Denied</Error></Errors></ApiResponse>",
                    status: status
                )
            }
            do {
                _ = try await service(transport).domainDetails(domain)
                XCTFail("Expected provider error")
            } catch let error as ProviderAPIError {
                if status == 200 { XCTAssertTrue(error.localizedDescription.contains("101: Denied")) }
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    private func service(_ transport: StubTransport, sleep: @escaping NamecheapService.Sleep = { _ in
    }) -> NamecheapService {
        NamecheapService(
            credentialsProvider: { ("unit-user", "unit-key", "192.0.2.1", nil) },
            transport: transport,
            sleep: sleep
        )
    }

    private func payload(
        _ name: String,
        _ type: String = "A",
        _ content: String = "192.0.2.1"
    ) -> CreateProviderRecordRequest {
        CreateProviderRecordRequest(
            name: name,
            type: type,
            content: content,
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        )
    }

    private func host(
        id: String = "1",
        name: String = "www",
        type: String = "A",
        address: String = "192.0.2.1"
    ) -> String {
        "<host HostId=\"\(id)\" Name=\"\(name)\" Type=\"\(type)\" Address=\"\(address)\" TTL=\"300\"/>"
    }

    private func hosts(_ request: URLRequest, _ hosts: [String]) throws -> (Data, URLResponse) {
        try xml(request, "<DomainDNSGetHostsResult IsUsingOurDNS=\"true\">\(hosts.joined())</DomainDNSGetHostsResult>")
    }

    private func xml(_ request: URLRequest, _ content: String) throws -> (Data, URLResponse) {
        try StubTransport.response(
            request,
            "<ApiResponse Status=\"OK\"><CommandResponse>\(content)</CommandResponse></ApiResponse>"
        )
    }
}
