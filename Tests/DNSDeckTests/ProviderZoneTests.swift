import XCTest
@testable import DNSDeckMCP

final class ProviderZoneTests: XCTestCase {
    // MARK: - ProviderZoneData Name Extraction

    func testCloudflareZoneName() throws {
        let cfZone = try JSONDecoder().decode(
            CFZone.self,
            from: XCTUnwrap("""
            {"id": "z1", "name": "example.com", "status": "active"}
            """.data(using: .utf8))
        )
        let zoneData = ProviderZoneData(snapshot: cfZone.snapshot())

        XCTAssertEqual(zoneData.name, "example.com")
        XCTAssertEqual(zoneData.id, "z1")
    }

    func testRoute53ZoneNameStripsTrailingDot() {
        let r53Zone = R53HostedZone(
            id: "/hostedzone/Z123",
            name: "example.com.",
            callerReference: nil,
            config: nil,
            resourceRecordSetCount: nil
        )
        let zoneData = ProviderZoneData(snapshot: r53Zone.snapshot())

        XCTAssertEqual(zoneData.name, "example.com")
    }

    func testRoute53ZoneNameWithoutTrailingDot() {
        let r53Zone = R53HostedZone(
            id: "/hostedzone/Z123",
            name: "example.com",
            callerReference: nil,
            config: nil,
            resourceRecordSetCount: nil
        )
        let zoneData = ProviderZoneData(snapshot: r53Zone.snapshot())

        XCTAssertEqual(zoneData.name, "example.com")
    }

    func testVercelDomainName() throws {
        let domain = try JSONDecoder().decode(
            VercelDomain.self,
            from: XCTUnwrap("""
            {"id": "d1", "name": "example.com"}
            """.data(using: .utf8))
        )
        let zoneData = ProviderZoneData(snapshot: domain.snapshot())

        XCTAssertEqual(zoneData.name, "example.com")
    }

    func testGoogleCloudZoneNameStripsTrailingDot() {
        let gcpZone = GCPManagedZone(
            id: "gcp-z1",
            name: "example-zone",
            dnsName: "example.com.",
            description: nil,
            visibility: nil,
            creationTime: nil,
            nameServers: nil
        )
        let zoneData = ProviderZoneData(snapshot: gcpZone.snapshot())

        XCTAssertEqual(zoneData.name, "example.com")
    }

    // MARK: - ProviderZone

    func testProviderZoneID() throws {
        let cfZone = try JSONDecoder().decode(
            CFZone.self,
            from: XCTUnwrap("""
            {"id": "z1", "name": "example.com", "status": "active"}
            """.data(using: .utf8))
        )
        let zone = ProviderZone(provider: .cloudflare, zone: cfZone, environmentId: UUID())

        XCTAssertEqual(zone.id, "cloudflare|z1")
        XCTAssertEqual(zone.name, "example.com")
        XCTAssertEqual(zone.provider, .cloudflare)
    }

    // MARK: - ProviderRecordData

    func testCloudflareRecordData() {
        let cfRecord = CFDNSRecord.makeForTesting(
            id: "rec-1",
            type: "A",
            name: "www.example.com",
            content: "192.168.1.1",
            ttl: 300,
            proxied: true,
            comment: "Test"
        )
        let recordData = ProviderRecordData(snapshot: cfRecord.snapshot())

        XCTAssertEqual(recordData.id, "rec-1")
        XCTAssertEqual(recordData.name, "www.example.com")
        XCTAssertEqual(recordData.type, "A")
        XCTAssertEqual(recordData.content, "192.168.1.1")
        XCTAssertEqual(recordData.ttl, 300)
        XCTAssertEqual(recordData.proxied, true)
        XCTAssertEqual(recordData.comment, "Test")
    }

    func testRoute53RecordDataContent() {
        let r53Record = R53ResourceRecordSet(
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
        let recordData = ProviderRecordData(snapshot: r53Record.snapshot())

        XCTAssertEqual(recordData.content, "192.168.1.1")
        XCTAssertNil(recordData.proxied)
        XCTAssertNil(recordData.priority)
    }

    func testRoute53RecordDataPreservesAllRRSetValues() {
        let r53Record = R53ResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            resourceRecords: [
                R53ResourceRecord(value: "192.0.2.1"),
                R53ResourceRecord(value: "192.0.2.2"),
            ],
            aliasTarget: nil,
            weight: 10,
            region: nil,
            geoLocation: nil,
            failover: nil,
            multiValueAnswer: true,
            setIdentifier: "weighted-primary",
            healthCheckId: "health-1"
        )
        let record = ProviderRecord(provider: .route53, record: r53Record)

        XCTAssertEqual(record.values, ["192.0.2.1", "192.0.2.2"])
        XCTAssertEqual(record.routingPolicy?.identifier, "weighted-primary")
        XCTAssertEqual(record.routingPolicy?.weight, 10)
        XCTAssertEqual(record.routingPolicy?.multiValueAnswer, true)
        XCTAssertEqual(record.routingPolicy?.healthCheckId, "health-1")
    }

    func testRoute53AliasRecordDataContent() {
        let r53Record = R53ResourceRecordSet(
            name: "example.com.",
            type: "A",
            ttl: nil,
            resourceRecords: nil,
            aliasTarget: R53AliasTarget(
                dnsName: "d12345.cloudfront.net.",
                hostedZoneId: "Z2FDTNDATAQYW2",
                evaluateTargetHealth: false
            ),
            weight: nil,
            region: nil,
            geoLocation: nil,
            failover: nil,
            multiValueAnswer: nil,
            setIdentifier: nil,
            healthCheckId: nil
        )
        let recordData = ProviderRecordData(snapshot: r53Record.snapshot())

        XCTAssertEqual(recordData.content, "d12345.cloudfront.net.")
    }

    func testVercelRecordDataPriority() throws {
        let vercelRecord = try JSONDecoder().decode(
            VercelDNSRecord.self,
            from: XCTUnwrap("""
            {"id": "vrec-1", "type": "MX", "name": "", "value": "mail.example.com", "mx": 10, "priority": 10}
            """.data(using: .utf8))
        )
        let recordData = ProviderRecordData(snapshot: vercelRecord.snapshot())

        XCTAssertEqual(recordData.priority, 10)
    }

    func testGCPRecordDataContent() {
        let gcpRecord = GCPResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            rrdatas: ["192.168.1.1", "192.168.1.2"]
        )
        let recordData = ProviderRecordData(snapshot: gcpRecord.snapshot())

        XCTAssertEqual(recordData.content, "192.168.1.1\n192.168.1.2")
    }

    // MARK: - ProviderRecord

    func testProviderRecordID() {
        let cfRecord = CFDNSRecord.makeForTesting(id: "rec-1")
        let record = ProviderRecord(provider: .cloudflare, record: cfRecord)

        XCTAssertEqual(record.id, "cloudflare|rec-1")
        XCTAssertEqual(record.provider, .cloudflare)
    }

    func testProviderRecordProperties() {
        let cfRecord = CFDNSRecord.makeForTesting(
            id: "rec-1",
            type: "MX",
            name: "example.com",
            content: "mail.example.com",
            ttl: 300,
            proxied: false,
            priority: 10,
            comment: "Mail server"
        )
        let record = ProviderRecord(provider: .cloudflare, record: cfRecord)

        XCTAssertEqual(record.name, "example.com")
        XCTAssertEqual(record.type, "MX")
        XCTAssertEqual(record.content, "mail.example.com")
        XCTAssertEqual(record.ttl, 300)
        XCTAssertEqual(record.proxied, false)
        XCTAssertEqual(record.priority, 10)
        XCTAssertEqual(record.comment, "Mail server")
    }

    func testGenericRecordSnapshotPreservesOpaqueProviderData() throws {
        let providerData = try XCTUnwrap(#"{"provider":"native"}"#.data(using: .utf8))
        let snapshot = ProviderRecordSnapshot(
            id: "rrset-1",
            name: "_service.example.com",
            type: "URI",
            values: ["10 1 \"https://one.example\"", "20 1 \"https://two.example\""],
            ttl: 600,
            aliasTarget: DNSAliasTarget(name: "target.example.com", zoneId: "zone-2", evaluateTargetHealth: true),
            routingPolicy: DNSRecordRoutingPolicy(
                identifier: "policy-1",
                weight: 20,
                region: "eu-west",
                continent: nil,
                country: nil,
                subdivision: nil,
                failover: nil,
                multiValueAnswer: nil,
                healthCheckId: "check-1"
            ),
            etag: "etag-1",
            metadata: ["providerField": "providerValue"],
            providerData: providerData
        )
        let record = ProviderRecord(provider: .cloudflare, snapshot: snapshot)

        XCTAssertEqual(record.values, snapshot.values)
        XCTAssertEqual(record.aliasTarget, snapshot.aliasTarget)
        XCTAssertEqual(record.routingPolicy, snapshot.routingPolicy)
        XCTAssertFalse(record.isEditable)
        let roundTripped = record.recordData.snapshot
        XCTAssertEqual(roundTripped.providerData, providerData)
        XCTAssertEqual(roundTripped.metadata["providerField"], "providerValue")
    }
}

protocol ProviderZoneFixture {
    func snapshot() -> ProviderZoneSnapshot
}

protocol ProviderRecordFixture {
    func snapshot() -> ProviderRecordSnapshot
}

extension CFZone: ProviderZoneFixture {}
extension R53HostedZone: ProviderZoneFixture {}
extension VercelDomain: ProviderZoneFixture {}
extension GCPManagedZone: ProviderZoneFixture {}
extension CFDNSRecord: ProviderRecordFixture {}
extension R53ResourceRecordSet: ProviderRecordFixture {}
extension VercelDNSRecord: ProviderRecordFixture {}
extension GCPResourceRecordSet: ProviderRecordFixture {}

extension ProviderZone {
    init(provider: DNSProvider, zone: some ProviderZoneFixture, environmentId: UUID) {
        self.init(provider: provider, snapshot: zone.snapshot(), environmentId: environmentId)
    }
}

extension ProviderRecord {
    init(provider: DNSProvider, record: some ProviderRecordFixture) {
        self.init(provider: provider, snapshot: record.snapshot())
    }
}
