import XCTest
@testable import DNSDeckMCP

final class ProviderRequestTests: XCTestCase {
    // MARK: - CreateProviderRecordRequest -> Cloudflare

    func testToCloudflareRequest() {
        let request = CreateProviderRecordRequest(
            name: "www",
            type: "A",
            content: "192.168.1.1",
            ttl: 300,
            proxied: true,
            priority: nil,
            comment: "Web server"
        )

        let cfRequest = request.toCloudflareRequest(zoneName: "example.com")

        XCTAssertEqual(cfRequest.type, "A")
        XCTAssertEqual(cfRequest.name, "www")
        XCTAssertEqual(cfRequest.content, "192.168.1.1")
        XCTAssertEqual(cfRequest.ttl, 300)
        XCTAssertEqual(cfRequest.proxied, true)
        XCTAssertNil(cfRequest.priority)
        XCTAssertNil(cfRequest.data)
        XCTAssertEqual(cfRequest.comment, "Web server")
    }

    // MARK: - CreateProviderRecordRequest -> Route53

    func testToRoute53RequestSimple() {
        let request = CreateProviderRecordRequest(
            name: "www",
            type: "A",
            content: "192.168.1.1",
            ttl: 600,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let r53Request = request.toRoute53Request()

        XCTAssertEqual(r53Request.name, "www")
        XCTAssertEqual(r53Request.type, "A")
        XCTAssertEqual(r53Request.ttl, 600)
        XCTAssertEqual(r53Request.values, ["192.168.1.1"])
    }

    func testToRoute53RequestDefaultTTL() {
        let request = CreateProviderRecordRequest(
            name: "www",
            type: "A",
            content: "192.168.1.1",
            ttl: nil,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let r53Request = request.toRoute53Request()

        XCTAssertEqual(r53Request.ttl, 300)
    }

    func testToRoute53RequestWithZoneName() {
        let request = CreateProviderRecordRequest(
            name: "www",
            type: "A",
            content: "192.168.1.1",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let r53Request = request.toRoute53Request(zoneName: "example.com")

        XCTAssertEqual(r53Request.name, "www.example.com.")
    }

    func testToRoute53RequestAtSymbol() {
        let request = CreateProviderRecordRequest(
            name: "@",
            type: "A",
            content: "192.168.1.1",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let r53Request = request.toRoute53Request(zoneName: "example.com")

        XCTAssertEqual(r53Request.name, "example.com.")
    }

    func testToRoute53RequestTrailingDot() {
        let request = CreateProviderRecordRequest(
            name: "www.example.com.",
            type: "A",
            content: "192.168.1.1",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let r53Request = request.toRoute53Request(zoneName: "example.com")

        XCTAssertEqual(r53Request.name, "www.example.com.")
    }

    // MARK: - CreateProviderRecordRequest -> Vercel

    func testToVercelRequest() {
        let request = CreateProviderRecordRequest(
            name: "www",
            type: "A",
            content: "192.168.1.1",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: "Test"
        )

        let vercelRequest = request.toVercelRequest(domain: "example.com")

        XCTAssertEqual(vercelRequest.type, "A")
        XCTAssertEqual(vercelRequest.name, "www")
        XCTAssertEqual(vercelRequest.value, "192.168.1.1")
        XCTAssertEqual(vercelRequest.comment, "Test")
    }

    func testToVercelRequestAtSymbol() {
        let request = CreateProviderRecordRequest(
            name: "@",
            type: "A",
            content: "192.168.1.1",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let vercelRequest = request.toVercelRequest(domain: "example.com")

        XCTAssertEqual(vercelRequest.name, "")
    }

    func testToVercelRequestStripsDomainSuffix() {
        let request = CreateProviderRecordRequest(
            name: "www.example.com",
            type: "A",
            content: "192.168.1.1",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let vercelRequest = request.toVercelRequest(domain: "example.com")

        XCTAssertEqual(vercelRequest.name, "www")
    }

    func testToVercelRequestMXPriority() {
        let request = CreateProviderRecordRequest(
            name: "@",
            type: "MX",
            content: "mail.example.com",
            ttl: 300,
            proxied: nil,
            priority: 10,
            comment: nil
        )

        let vercelRequest = request.toVercelRequest(domain: "example.com")

        XCTAssertEqual(vercelRequest.mxPriority, 10)
    }

    // MARK: - CreateProviderRecordRequest -> Google Cloud

    func testToGoogleCloudRequest() {
        let request = CreateProviderRecordRequest(
            name: "www",
            type: "A",
            content: "192.168.1.1",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let gcpRequest = request.toGoogleCloudRequest(zoneName: "example.com.")

        XCTAssertEqual(gcpRequest.name, "www.example.com.")
        XCTAssertEqual(gcpRequest.type, "A")
        XCTAssertEqual(gcpRequest.ttl, 300)
        XCTAssertEqual(gcpRequest.rrdatas, ["192.168.1.1"])
    }

    func testToGoogleCloudRequestAtSymbol() {
        let request = CreateProviderRecordRequest(
            name: "@",
            type: "A",
            content: "192.168.1.1",
            ttl: 300,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let gcpRequest = request.toGoogleCloudRequest(zoneName: "example.com.")

        XCTAssertTrue(gcpRequest.name.contains("example.com"))
    }

    func testToGoogleCloudRequestDefaultTTL() {
        let request = CreateProviderRecordRequest(
            name: "www",
            type: "A",
            content: "192.168.1.1",
            ttl: nil,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let gcpRequest = request.toGoogleCloudRequest(zoneName: "example.com.")

        XCTAssertEqual(gcpRequest.ttl, DNSProvider.googleCloud.defaultTTL)
    }

    func testToGoogleCloudRequestMXWithPriority() {
        let request = CreateProviderRecordRequest(
            name: "@",
            type: "MX",
            content: "mail.example.com",
            ttl: 300,
            proxied: nil,
            priority: 10,
            comment: nil
        )

        let gcpRequest = request.toGoogleCloudRequest(zoneName: "example.com.")

        XCTAssertEqual(gcpRequest.rrdatas, ["10 mail.example.com."])
    }

    // MARK: - UpdateProviderRecordRequest -> Cloudflare

    func testUpdateToCloudflareRequest() {
        let request = UpdateProviderRecordRequest(
            name: "www2",
            type: "A",
            content: "10.0.0.1",
            ttl: 600,
            proxied: false,
            priority: nil,
            comment: "Updated"
        )

        let cfRequest = request.toCloudflareRequest(zoneName: "example.com")

        XCTAssertEqual(cfRequest.name, "www2")
        XCTAssertEqual(cfRequest.content, "10.0.0.1")
        XCTAssertEqual(cfRequest.ttl, 600)
        XCTAssertEqual(cfRequest.proxied, false)
        XCTAssertEqual(cfRequest.comment, "Updated")
    }

    // MARK: - UpdateProviderRecordRequest -> Route53

    func testUpdateToRoute53Request() {
        let oldRecord = R53ResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            resourceRecords: [R53ResourceRecord(value: "192.168.1.1")],
            aliasTarget: nil,
            weight: nil,
            region: nil,
            geoLocation: nil,
            failover: nil,
            multiValueAnswer: nil,
            setIdentifier: nil,
            healthCheckId: nil
        )

        let request = UpdateProviderRecordRequest(
            name: "www2",
            type: nil,
            content: "10.0.0.1",
            ttl: 600,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let r53Request = request.toRoute53Request(oldRecord: oldRecord, zoneName: "example.com")

        XCTAssertEqual(r53Request.newRecord.name, "www2.example.com.")
        XCTAssertEqual(r53Request.newRecord.ttl, 600)
        XCTAssertEqual(r53Request.newRecord.resourceRecords?.first?.value, "10.0.0.1")
    }

    func testUpdateToRoute53RequestPreservesOldValues() {
        let oldRecord = R53ResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            resourceRecords: [R53ResourceRecord(value: "192.168.1.1")],
            aliasTarget: nil,
            weight: nil,
            region: nil,
            geoLocation: nil,
            failover: nil,
            multiValueAnswer: nil,
            setIdentifier: nil,
            healthCheckId: nil
        )

        let request = UpdateProviderRecordRequest(
            name: nil,
            type: nil,
            content: nil,
            ttl: nil,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let r53Request = request.toRoute53Request(oldRecord: oldRecord)

        XCTAssertEqual(r53Request.newRecord.name, oldRecord.name)
        XCTAssertEqual(r53Request.newRecord.ttl, oldRecord.ttl)
        XCTAssertEqual(r53Request.newRecord.resourceRecords?.first?.value, "192.168.1.1")
    }

    func testUpdateToRoute53RequestPreservesAliasTarget() {
        let oldRecord = R53ResourceRecordSet(
            name: "example.com.",
            type: "A",
            ttl: nil,
            resourceRecords: nil,
            aliasTarget: R53AliasTarget(
                dnsName: "old-target.example.net.",
                hostedZoneId: "ZALIAS",
                evaluateTargetHealth: true
            ),
            weight: nil,
            region: nil,
            geoLocation: nil,
            failover: nil,
            multiValueAnswer: nil,
            setIdentifier: nil,
            healthCheckId: nil
        )

        let request = UpdateProviderRecordRequest(
            aliasTarget: "new-target.example.net."
        )

        let r53Request = request.toRoute53Request(oldRecord: oldRecord)

        XCTAssertEqual(r53Request.newRecord.aliasTarget?.dnsName, "new-target.example.net.")
        XCTAssertEqual(r53Request.newRecord.aliasTarget?.hostedZoneId, "ZALIAS")
        XCTAssertEqual(r53Request.newRecord.aliasTarget?.evaluateTargetHealth, true)
    }

    func testUpdateToRoute53RequestUsesAllValues() {
        let oldRecord = R53ResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            resourceRecords: [R53ResourceRecord(value: "192.168.1.1")],
            aliasTarget: nil,
            weight: nil,
            region: nil,
            geoLocation: nil,
            failover: nil,
            multiValueAnswer: true,
            setIdentifier: nil,
            healthCheckId: nil
        )

        let request = UpdateProviderRecordRequest(
            values: ["10.0.0.1", "10.0.0.2"]
        )

        let r53Request = request.toRoute53Request(oldRecord: oldRecord)

        XCTAssertEqual(r53Request.newRecord.resourceRecords?.map(\.value), ["10.0.0.1", "10.0.0.2"])
    }

    // MARK: - UpdateProviderRecordRequest -> Vercel

    func testUpdateToVercelRequest() {
        let request = UpdateProviderRecordRequest(
            name: "www2",
            type: "A",
            content: "10.0.0.1",
            ttl: 600,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let vercelRequest = request.toVercelRequest(domain: "example.com")

        XCTAssertEqual(vercelRequest.name, "www2")
        XCTAssertEqual(vercelRequest.value, "10.0.0.1")
    }

    func testUpdateToVercelRequestAtSymbol() {
        let request = UpdateProviderRecordRequest(
            name: "@",
            type: nil,
            content: nil,
            ttl: nil,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let vercelRequest = request.toVercelRequest(domain: "example.com")

        XCTAssertEqual(vercelRequest.name, "")
    }

    func testUpdateToVercelRequestPreservesExistingComment() {
        let existingRecord = VercelDNSRecord(
            id: "vrec-1",
            type: "A",
            name: "www",
            value: "192.168.1.1",
            priority: nil,
            ttl: 300,
            comment: "Existing comment",
            created: nil,
            updated: nil,
            mxPriority: nil,
            mx: nil,
            verified: nil,
            slug: nil
        )

        let request = UpdateProviderRecordRequest(content: "10.0.0.1")
        let vercelRequest = request.toVercelRequest(domain: "example.com", existingRecord: existingRecord)

        XCTAssertEqual(vercelRequest.comment, "Existing comment")
    }

    // MARK: - UpdateProviderRecordRequest -> Google Cloud

    func testUpdateToGoogleCloudRequest() {
        let oldRecord = GCPResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            rrdatas: ["192.168.1.1"]
        )

        let request = UpdateProviderRecordRequest(
            name: nil,
            type: nil,
            content: "10.0.0.1",
            ttl: 600,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let gcpRequest = request.toGoogleCloudRequest(oldRecord: oldRecord, zoneName: "example.com.")

        XCTAssertEqual(gcpRequest.name, "www.example.com.")
        XCTAssertEqual(gcpRequest.type, "A")
        XCTAssertEqual(gcpRequest.ttl, 600)
        XCTAssertEqual(gcpRequest.rrdatas, ["10.0.0.1"])
    }

    func testUpdateToGoogleCloudRequestPreservesOldContent() {
        let oldRecord = GCPResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            rrdatas: ["192.168.1.1"]
        )

        let request = UpdateProviderRecordRequest(
            name: nil,
            type: nil,
            content: nil,
            ttl: nil,
            proxied: nil,
            priority: nil,
            comment: nil
        )

        let gcpRequest = request.toGoogleCloudRequest(oldRecord: oldRecord, zoneName: "example.com.")

        XCTAssertEqual(gcpRequest.rrdatas, ["192.168.1.1"])
        XCTAssertEqual(gcpRequest.ttl, 300)
    }

    func testUpdateToGoogleCloudRequestUsesValuesArray() {
        let oldRecord = GCPResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            rrdatas: ["192.168.1.1"]
        )

        let request = UpdateProviderRecordRequest(values: ["10.0.0.1", "10.0.0.2"])
        let gcpRequest = request.toGoogleCloudRequest(oldRecord: oldRecord, zoneName: "example.com.")

        XCTAssertEqual(gcpRequest.rrdatas, ["10.0.0.1", "10.0.0.2"])
    }

    func testUpdateToCloudflareRequestUsesStructuredSRVData() {
        let existingRecord = CFDNSRecord.makeForTesting(
            type: "SRV",
            name: "_sip._tcp.example.com",
            content: "10 5 5060 sip-old.example.com",
            data: RecordData(
                service: "_sip",
                proto: "_tcp",
                name: "example.com",
                priority: 10,
                weight: 5,
                port: 5060,
                target: "sip-old.example.com",
                flags: nil,
                tag: nil,
                value: nil
            )
        )

        let request = UpdateProviderRecordRequest(
            name: "_sip._tcp.staging.example.com",
            type: "SRV",
            recordData: UpdateProviderRecordRequest.cloudflareSRVData(
                zoneName: "example.com",
                name: "_sip._tcp.staging.example.com",
                content: "10 5 5060 sip-new.example.com"
            )
        )

        let cfRequest = request.toCloudflareRequest(zoneName: "example.com", existingRecord: existingRecord)

        XCTAssertEqual(cfRequest.name, "_sip._tcp.staging.example.com")
        XCTAssertNil(cfRequest.content)
        guard case let .components(data) = cfRequest.data else {
            return XCTFail("Expected structured SRV data")
        }
        XCTAssertEqual(data.target, "sip-new.example.com")
        XCTAssertEqual(data.name, "staging.example.com")
    }
}
