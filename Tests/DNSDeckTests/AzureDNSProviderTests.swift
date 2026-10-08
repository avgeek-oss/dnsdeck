import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class AzureDNSProviderTests: XCTestCase {
    func testOAuthClientCredentialsRequestIsExactAndTokenIsCached() async throws {
        let transport = AzureDNSRecordingTransport { request, _ in
            if request.url?.host == "login.azure.test" {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/tenant-id/oauth2/v2.0/token")
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Content-Type"),
                    "application/x-www-form-urlencoded"
                )
                XCTAssertEqual(
                    try String(decoding: XCTUnwrap(request.httpBody), as: UTF8.self),
                    "client_id=client-id&client_secret=s3cr%26t&grant_type=client_credentials&scope=" +
                        "https%3A%2F%2Fmanagement.azure.com%2F.default"
                )
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"access_token":"fixture-token","expires_in":3600}"#
                )
            }

            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
            return try Self.response(request: request, status: 200, body: #"{"value":[]}"#)
        }
        let service = try AzureDNSService(
            credentialsProvider: Self.credentials,
            resourceManagerBaseURL: XCTUnwrap(URL(string: "https://management.azure.test")),
            identityBaseURL: XCTUnwrap(URL(string: "https://login.azure.test")),
            transport: transport,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1000) }
        )

        _ = try await service.listZones()
        _ = try await service.listZones()

        XCTAssertEqual(transport.requests.filter { $0.url?.host == "login.azure.test" }.count, 1)
        XCTAssertEqual(transport.requests.filter { $0.url?.host == "management.azure.test" }.count, 2)
    }

    func testOAuthErrorSurfacesDescriptionAndCorrelationID() async throws {
        let transport = AzureDNSRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 401,
                body: #"{"error":"invalid_client","error_description":"The client secret is invalid.","correlation_id":"correlation-42"}"#
            )
        }
        let service = try AzureDNSService(
            credentialsProvider: Self.credentials,
            resourceManagerBaseURL: XCTUnwrap(URL(string: "https://management.azure.test")),
            identityBaseURL: XCTUnwrap(URL(string: "https://login.azure.test")),
            transport: transport,
            sleep: { _ in }
        )

        do {
            _ = try await service.listZones()
            XCTFail("Expected OAuth error")
        } catch let ProviderAPIError.http(provider, statusCode, message, requestId, _) {
            XCTAssertEqual(provider, .azureDNS)
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "The client secret is invalid.")
            XCTAssertEqual(requestId, "correlation-42")
        }
    }

    func testSubscriptionZoneListingFollowsEveryTrustedNextLink() async throws {
        let transport = AzureDNSRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/subscriptions/sub-id/providers/Microsoft.Network/dnszones")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
            if index == 0 {
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"value":[{"id":"/subscriptions/sub-id/resourceGroups/rg-one/providers/Microsoft.Network/dnsZones/one.example","name":"one.example","type":"Microsoft.Network/dnsZones","location":"global","etag":"zone-1","properties":{"nameServers":["ns1.azure-dns.com"],"zoneType":"Public"}}],"nextLink":"https://management.azure.test/subscriptions/sub-id/providers/Microsoft.Network/dnszones?api-version=2018-05-01&$skiptoken=next"}"#
                )
            }
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"value":[{"id":"/subscriptions/sub-id/resourceGroups/rg-two/providers/Microsoft.Network/dnsZones/two.example","name":"two.example","type":"Microsoft.Network/dnsZones","location":"global","etag":"zone-2","properties":{"nameServers":[],"zoneType":"Public"}}]}"#
            )
        }

        let zones = try await makeService(transport: transport).listZones()

        XCTAssertEqual(zones.map(\.name), ["one.example", "two.example"])
        XCTAssertEqual(zones.map(\.resourceGroup), ["rg-one", "rg-two"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testZoneListingRejectsUntrustedAndCyclicNextLinks() async throws {
        let untrusted = AzureDNSRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 200,
                body: #"{"value":[],"nextLink":"https://attacker.example/steal"}"#
            )
        }
        do {
            _ = try await makeService(transport: untrusted).listZones()
            XCTFail("Expected untrusted pagination URL")
        } catch let ProviderAPIError.untrustedURL(provider, url) {
            XCTAssertEqual(provider, .azureDNS)
            XCTAssertEqual(url.host, "attacker.example")
        }

        let cyclic = AzureDNSRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 200,
                body: #"{"value":[],"nextLink":"https://management.azure.test/subscriptions/sub-id/providers/Microsoft.Network/dnszones?api-version=2018-05-01"}"#
            )
        }
        do {
            _ = try await makeService(transport: cyclic).listZones()
            XCTFail("Expected pagination cycle")
        } catch let ProviderAPIError.operationFailed(provider, operation, message) {
            XCTAssertEqual(provider, .azureDNS)
            XCTAssertEqual(operation, "zone listing")
            XCTAssertEqual(message, "the API returned a pagination cycle")
        }
    }

    func testRecordSetListingFollowsNextLinkAndMapsEveryStableShape() async throws {
        let transport = AzureDNSRecordingTransport { request, index in
            XCTAssertEqual(
                request.url?.path,
                "/subscriptions/sub-id/resourceGroups/rg-one/providers/Microsoft.Network/dnsZones/example.com/all"
            )
            if index == 0 {
                return try Self.response(
                    request: request,
                    status: 200,
                    body: Self.recordPageOne
                )
            }
            return try Self.response(request: request, status: 200, body: Self.recordPageTwo)
        }
        let adapter = AzureDNSProviderService(service: makeService(transport: transport))

        let records = try await adapter.records(for: providerZone())

        XCTAssertEqual(records.count, 11)
        XCTAssertEqual(records.first(where: { $0.type == "A" && $0.aliasTarget == nil })?.values, [
            "192.0.2.1", "192.0.2.2",
        ])
        XCTAssertEqual(records.first(where: { $0.type == "AAAA" })?.values, ["2001:db8::1"])
        XCTAssertEqual(records.first(where: { $0.type == "CAA" })?.values, ["0 issue letsencrypt.org"])
        XCTAssertEqual(records.first(where: { $0.type == "CNAME" })?.values, ["target.example.net."])
        XCTAssertEqual(records.first(where: { $0.type == "MX" })?.values, ["10 mail.example.net."])
        XCTAssertEqual(records.first(where: { $0.type == "NS" })?.values, ["ns.example.net."])
        XCTAssertEqual(records.first(where: { $0.type == "PTR" })?.values, ["host.example.com."])
        XCTAssertEqual(records.first(where: { $0.type == "SRV" })?.values, ["5 10 443 sip.example.net."])
        XCTAssertEqual(records.first(where: { $0.type == "TXT" })?.values, ["hello world"])
        XCTAssertFalse(try XCTUnwrap(records.first(where: { $0.type == "SOA" })).isEditable)
        XCTAssertEqual(
            records.first(where: { $0.aliasTarget != nil })?.aliasTarget?.name,
            "/subscriptions/target/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/ip"
        )
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testMappingsCoverStableRecordTypesAliasesAndTXTChunking() throws {
        let caa = try request(type: "CAA", values: ["0 issue letsencrypt.org"]).toAzureDNSMutation(
            zoneName: "example.com"
        )
        XCTAssertEqual(caa.request.properties.caaRecords?.first?.flags, 0)
        XCTAssertEqual(caa.request.properties.caaRecords?.first?.tag, "issue")

        let mx = try request(type: "MX", values: ["10 mail-one.example.", "20 mail-two.example."])
            .toAzureDNSMutation(zoneName: "example.com")
        XCTAssertEqual(mx.request.properties.mxRecords?.map(\.preference), [10, 20])

        let srv = try request(type: "SRV", values: ["5 10 443 sip.example."])
            .toAzureDNSMutation(zoneName: "example.com")
        XCTAssertEqual(srv.request.properties.srvRecords?.first?.port, 443)

        let longTXT = String(repeating: "a", count: 256)
        let txt = try request(type: "TXT", values: [longTXT]).toAzureDNSMutation(zoneName: "example.com")
        XCTAssertEqual(txt.request.properties.txtRecords?.first?.value?.map(\.utf8.count), [255, 1])

        XCTAssertEqual(
            try request(type: "A", values: ["192.0.2.1", "192.0.2.2"])
                .toAzureDNSMutation(zoneName: "example.com").request.properties.aRecords?.count,
            2
        )
        XCTAssertEqual(
            try request(type: "AAAA", values: ["2001:db8::1"])
                .toAzureDNSMutation(zoneName: "example.com").request.properties.aaaaRecords?.count,
            1
        )
        XCTAssertEqual(
            try request(type: "CNAME", values: ["target.example."])
                .toAzureDNSMutation(zoneName: "example.com").request.properties.cnameRecord?.cname,
            "target.example."
        )
        XCTAssertEqual(
            try request(type: "NS", values: ["ns.example."])
                .toAzureDNSMutation(zoneName: "example.com").request.properties.nsRecords?.count,
            1
        )
        XCTAssertEqual(
            try request(type: "PTR", values: ["host.example."])
                .toAzureDNSMutation(zoneName: "example.com").request.properties.ptrRecords?.count,
            1
        )

        let target = "/subscriptions/target/resourceGroups/rg/providers/Microsoft.Network/trafficManagerProfiles/tm"
        let alias = try CreateProviderRecordRequest(
            name: "edge.example.com",
            type: "A",
            content: target,
            ttl: 60,
            proxied: nil,
            priority: nil,
            comment: nil,
            aliasTarget: target
        ).toAzureDNSMutation(zoneName: "example.com")
        XCTAssertEqual(alias.relativeName, "edge")
        XCTAssertEqual(alias.request.properties.targetResource?.id, target)
        XCTAssertNil(alias.request.properties.aRecords)
    }

    func testCreateAndSameIdentityUpdateUseConditionalPutHeaders() async throws {
        let transport = AzureDNSRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "PUT")
            if index == 0 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "*")
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "record-etag")
            }
            let body = try JSONDecoder().decode(
                AzureDNSRecordSetWriteRequestFixture.self,
                from: XCTUnwrap(request.httpBody)
            )
            XCTAssertEqual(body.properties.ttl, index == 0 ? 300 : 600)
            return try Self.response(request: request, status: 200, body: Self.aRecordResponse(etag: "new-etag"))
        }
        let adapter = AzureDNSProviderService(service: makeService(transport: transport))
        let zone = providerZone()

        try await adapter.createRecord(in: zone, payload: request(type: "A", values: ["192.0.2.1"]))
        try await adapter.updateRecord(
            in: zone,
            record: providerRecord(),
            edits: UpdateProviderRecordRequest(ttl: 600)
        )

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRenameRollsBackDestinationWhenSourceDeleteFails() async throws {
        let transport = AzureDNSRecordingTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path.split(separator: "/").last, "renamed")
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "*")
                return try Self.response(
                    request: request,
                    status: 201,
                    body: Self.aRecordResponse(name: "renamed", etag: "created-etag")
                )
            }
            if index == 1 {
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "record-etag")
                return try Self.response(
                    request: request,
                    status: 412,
                    body: #"{"error":{"code":"PreconditionFailed","message":"The record changed."}}"#
                )
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path.split(separator: "/").last, "renamed")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "created-etag")
            return try Self.response(request: request, status: 204, body: "")
        }
        let adapter = AzureDNSProviderService(service: makeService(transport: transport))

        do {
            try await adapter.updateRecord(
                in: providerZone(),
                record: providerRecord(),
                edits: UpdateProviderRecordRequest(name: "renamed")
            )
            XCTFail("Expected source delete failure")
        } catch let ProviderAPIError.http(provider, statusCode, _, _, _) {
            XCTAssertEqual(provider, .azureDNS)
            XCTAssertEqual(statusCode, 412)
        }
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testZoneCreateAndAsynchronousDeleteFollowARMContracts() async throws {
        var delays: [TimeInterval] = []
        let transport = AzureDNSRecordingTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "*")
                XCTAssertEqual(request.url?.path, Self.zonePath)
                XCTAssertEqual(
                    try String(decoding: XCTUnwrap(request.httpBody), as: UTF8.self),
                    #"{"location":"global"}"#
                )
                return try Self.response(request: request, status: 201, body: Self.zoneResponse)
            }
            if index == 1 {
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "zone-etag")
                return try Self.response(
                    request: request,
                    status: 202,
                    body: "",
                    headers: [
                        "Azure-AsyncOperation": "https://management.azure.test/operations/delete-42",
                        "Retry-After": "0",
                    ]
                )
            }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/operations/delete-42")
            return try Self.response(
                request: request,
                status: 200,
                body: index == 2 ? #"{"status":"InProgress"}"# : #"{"status":"Succeeded"}"#,
                headers: ["Retry-After": "0"]
            )
        }
        let service = makeService(transport: transport, sleep: { delays.append($0) })
        let adapter = AzureDNSProviderService(service: service)

        let created = try await adapter.createZone(named: "example.com", environmentId: UUID())
        try await adapter.deleteZone(created)

        XCTAssertEqual(created.nameservers, ["ns1.azure-dns.com"])
        XCTAssertEqual(delays, [0, 0])
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testMutationRetriesOnlyRateLimitAndPendingOperationResponses() async throws {
        var delays: [TimeInterval] = []
        let transport = AzureDNSRecordingTransport { request, index in
            if index == 0 {
                return try Self.response(
                    request: request,
                    status: 409,
                    body: #"{"error":{"code":"Conflict","message":"Another operation is pending for requested object"}}"#,
                    headers: ["Retry-After": "0"]
                )
            }
            if index == 1 {
                return try Self.response(
                    request: request,
                    status: 429,
                    body: #"{"error":{"code":"TooManyRequests","message":"Slow down."}}"#,
                    headers: ["Retry-After": "0"]
                )
            }
            return try Self.response(request: request, status: 200, body: Self.aRecordResponse())
        }
        let service = makeService(transport: transport, sleep: { delays.append($0) })
        let mutation = try request(type: "A", values: ["192.0.2.1"]).toAzureDNSMutation(
            zoneName: "example.com"
        )

        _ = try await service.putRecordSet(zone: nativeZone(), mutation: mutation, ifNoneMatch: "*")

        XCTAssertEqual(delays, [0, 0])
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertTrue(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "If-None-Match") == "*" })
    }

    func testMutationDoesNotRetryAmbiguousTransportFailureOrPermanentConflict() async throws {
        let transportFailure = AzureDNSRecordingTransport { _, _ in
            throw URLError(.networkConnectionLost)
        }
        let service = makeService(transport: transportFailure)
        let mutation = try request(type: "A", values: ["192.0.2.1"]).toAzureDNSMutation(
            zoneName: "example.com"
        )
        do {
            _ = try await service.putRecordSet(zone: nativeZone(), mutation: mutation, ifNoneMatch: "*")
            XCTFail("Expected transport failure")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        }
        XCTAssertEqual(transportFailure.requests.count, 1)

        let permanentConflict = AzureDNSRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 409,
                body: #"{"error":{"code":"Conflict","message":"A CNAME already exists."}}"#
            )
        }
        do {
            _ = try await makeService(transport: permanentConflict).putRecordSet(
                zone: nativeZone(),
                mutation: mutation,
                ifNoneMatch: "*"
            )
            XCTFail("Expected permanent conflict")
        } catch let ProviderAPIError.http(provider, statusCode, message, _, _) {
            XCTAssertEqual(provider, .azureDNS)
            XCTAssertEqual(statusCode, 409)
            XCTAssertEqual(message, "A CNAME already exists.")
        }
        XCTAssertEqual(permanentConflict.requests.count, 1)
    }

    func testAzureErrorIncludesARMRequestID() async throws {
        let transport = AzureDNSRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 412,
                body: #"{"error":{"code":"PreconditionFailed","message":"The ETag no longer matches."}}"#,
                headers: ["x-ms-request-id": "request-42"]
            )
        }
        do {
            try await makeService(transport: transport).deleteRecordSet(
                zone: nativeZone(),
                relativeName: "www",
                type: "A",
                etag: "old-etag"
            )
            XCTFail("Expected ETag failure")
        } catch let ProviderAPIError.http(provider, statusCode, message, requestId, _) {
            XCTAssertEqual(provider, .azureDNS)
            XCTAssertEqual(statusCode, 412)
            XCTAssertEqual(message, "The ETag no longer matches.")
            XCTAssertEqual(requestId, "request-42")
        }
    }

    private static let zonePath = "/subscriptions/sub-id/resourceGroups/rg-default/providers/Microsoft.Network/dnsZones/example.com"

    private static let zoneResponse = #"{"id":"/subscriptions/sub-id/resourceGroups/rg-default/providers/Microsoft.Network/dnsZones/example.com","name":"example.com","type":"Microsoft.Network/dnsZones","location":"global","etag":"zone-etag","properties":{"nameServers":["ns1.azure-dns.com"],"zoneType":"Public","numberOfRecordSets":2}}"#

    private static let recordPageOne = #"{"value":[{"id":"/records/a","name":"www","type":"Microsoft.Network/dnsZones/A","etag":"a","properties":{"TTL":300,"fqdn":"www.example.com.","ARecords":[{"ipv4Address":"192.0.2.1"},{"ipv4Address":"192.0.2.2"}]}},{"id":"/records/aaaa","name":"v6","type":"Microsoft.Network/dnsZones/AAAA","etag":"aaaa","properties":{"TTL":300,"fqdn":"v6.example.com.","AAAARecords":[{"ipv6Address":"2001:db8::1"}]}},{"id":"/records/caa","name":"@","type":"Microsoft.Network/dnsZones/CAA","etag":"caa","properties":{"TTL":300,"fqdn":"example.com.","caaRecords":[{"flags":0,"tag":"issue","value":"letsencrypt.org"}]}},{"id":"/records/cname","name":"alias","type":"Microsoft.Network/dnsZones/CNAME","etag":"cname","properties":{"TTL":300,"fqdn":"alias.example.com.","CNAMERecord":{"cname":"target.example.net."}}},{"id":"/records/mx","name":"@","type":"Microsoft.Network/dnsZones/MX","etag":"mx","properties":{"TTL":300,"fqdn":"example.com.","MXRecords":[{"preference":10,"exchange":"mail.example.net."}]}},{"id":"/records/ns","name":"child","type":"Microsoft.Network/dnsZones/NS","etag":"ns","properties":{"TTL":300,"fqdn":"child.example.com.","NSRecords":[{"nsdname":"ns.example.net."}]}},{"id":"/records/ptr","name":"1","type":"Microsoft.Network/dnsZones/PTR","etag":"ptr","properties":{"TTL":300,"fqdn":"1.example.com.","PTRRecords":[{"ptrdname":"host.example.com."}]}},{"id":"/records/srv","name":"_sip._tcp","type":"Microsoft.Network/dnsZones/SRV","etag":"srv","properties":{"TTL":300,"fqdn":"_sip._tcp.example.com.","SRVRecords":[{"priority":5,"weight":10,"port":443,"target":"sip.example.net."}]}},{"id":"/records/txt","name":"@","type":"Microsoft.Network/dnsZones/TXT","etag":"txt","properties":{"TTL":300,"fqdn":"example.com.","TXTRecords":[{"value":["hello ","world"]}]}},{"id":"/records/soa","name":"@","type":"Microsoft.Network/dnsZones/SOA","etag":"soa","properties":{"TTL":3600,"fqdn":"example.com.","SOARecord":{"host":"ns1.azure-dns.com.","email":"hostmaster.example.com.","serialNumber":1,"refreshTime":3600,"retryTime":300,"expireTime":2419200,"minimumTTL":300}}}],"nextLink":"https://management.azure.test/subscriptions/sub-id/resourceGroups/rg-one/providers/Microsoft.Network/dnsZones/example.com/all?api-version=2018-05-01&$skiptoken=next"}"#

    private static let recordPageTwo = #"{"value":[{"id":"/records/alias","name":"edge","type":"Microsoft.Network/dnsZones/A","etag":"alias","properties":{"TTL":60,"fqdn":"edge.example.com.","targetResource":{"id":"/subscriptions/target/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/ip"},"provisioningState":"Succeeded"}}]}"#

    private static func credentials() -> AzureDNSService.Credentials {
        (
            tenantId: "tenant-id",
            clientId: "client-id",
            clientSecret: "s3cr&t",
            subscriptionId: "sub-id",
            resourceGroup: "rg-default"
        )
    }

    private func makeService(
        transport: AzureDNSRecordingTransport,
        sleep: @escaping ProviderHTTPClient.Sleep = { _ in }
    ) -> AzureDNSService {
        AzureDNSService(
            credentialsProvider: Self.credentials,
            resourceManagerBaseURL: URL(string: "https://management.azure.test")!,
            identityBaseURL: URL(string: "https://login.azure.test")!,
            transport: transport,
            sleep: sleep,
            accessTokenProvider: { "fixture-token" }
        )
    }

    private func nativeZone() -> AzureDNSZone {
        AzureDNSZone(
            id: "/subscriptions/sub-id/resourceGroups/rg-one/providers/Microsoft.Network/dnsZones/example.com",
            name: "example.com",
            type: "Microsoft.Network/dnsZones",
            location: "global",
            tags: nil,
            etag: "zone-etag",
            properties: AzureDNSZoneProperties(
                maxNumberOfRecordSets: 5000,
                maxNumberOfRecordsPerRecordSet: nil,
                numberOfRecordSets: 2,
                nameServers: ["ns1.azure-dns.com"],
                zoneType: "Public"
            )
        )
    }

    private func providerZone() -> ProviderZone {
        ProviderZone(provider: .azureDNS, snapshot: nativeZone().snapshot(), environmentId: UUID())
    }

    private func providerRecord() -> ProviderRecord {
        ProviderRecord(
            provider: .azureDNS,
            snapshot: AzureDNSRecordSet(
                id: "/records/a",
                name: "www",
                type: "Microsoft.Network/dnsZones/A",
                etag: "record-etag",
                properties: AzureDNSRecordSetProperties(
                    metadata: ["owner": "dnsdeck"],
                    ttl: 300,
                    aRecords: [AzureDNSARecord(ipv4Address: "192.0.2.1")]
                )
            ).snapshot(zoneName: "example.com")
        )
    }

    private func request(type: String, values: [String]) -> CreateProviderRecordRequest {
        Self.request(type: type, values: values)
    }

    private static func request(type: String, values: [String]) -> CreateProviderRecordRequest {
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

    private static func aRecordResponse(
        name: String = "www",
        etag: String = "record-etag"
    ) -> String {
        #"{"id":"/records/\#(name)","name":"\#(name)","type":"Microsoft.Network/dnsZones/A","etag":"\#(etag)","properties":{"TTL":300,"fqdn":"\#(name).example.com.","ARecords":[{"ipv4Address":"192.0.2.1"}]}}"#
    }

    private static func response(
        request: URLRequest,
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
}

private struct AzureDNSRecordSetWriteRequestFixture: Decodable {
    struct Properties: Decodable {
        let ttl: Int

        enum CodingKeys: String, CodingKey {
            case ttl = "TTL"
        }
    }

    let properties: Properties
}

@MainActor
private final class AzureDNSRecordingTransport: NetworkTransport {
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
