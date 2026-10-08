import XCTest
@testable import DNSDeckMCP

final class ModelCodingTests: XCTestCase {
    // MARK: - DNSEnvironment Encoding/Decoding

    func testDNSEnvironmentEncoding() throws {
        let env = try DNSEnvironment(
            id: XCTUnwrap(UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")),
            name: "Production",
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            isStarred: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(env)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DNSEnvironment.self, from: data)

        XCTAssertEqual(decoded.id, env.id)
        XCTAssertEqual(decoded.name, env.name)
        XCTAssertEqual(decoded.createdAt, env.createdAt)
        XCTAssertEqual(decoded.isStarred, true)
    }

    func testDNSEnvironmentDecodingWithoutIsStarred() throws {
        // Test backward compatibility: isStarred should default to false
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "name": "Staging",
            "createdAt": 1000000
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DNSEnvironment.self, from: data)

        XCTAssertEqual(decoded.name, "Staging")
        XCTAssertEqual(decoded.isStarred, false)
    }

    func testDNSEnvironmentIdentifiable() {
        let id = UUID()
        let env = DNSEnvironment(id: id, name: "Test")
        XCTAssertEqual(env.id, id)
    }

    func testDNSEnvironmentHashable() {
        let id = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let env1 = DNSEnvironment(id: id, name: "Test", createdAt: fixedDate)
        let env2 = DNSEnvironment(id: id, name: "Test", createdAt: fixedDate)
        XCTAssertEqual(env1, env2)

        let set: Set<DNSEnvironment> = [env1, env2]
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - CFZone Decoding

    func testCFZoneDecoding() throws {
        let json = """
        {
            "id": "zone-123",
            "name": "example.com",
            "status": "active"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let zone = try JSONDecoder().decode(CFZone.self, from: data)

        XCTAssertEqual(zone.id, "zone-123")
        XCTAssertEqual(zone.name, "example.com")
        XCTAssertEqual(zone.status, "active")
    }

    func testCFZoneDecodingWithNullStatus() throws {
        let json = """
        {
            "id": "zone-123",
            "name": "example.com",
            "status": null
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let zone = try JSONDecoder().decode(CFZone.self, from: data)

        XCTAssertNil(zone.status)
    }

    // MARK: - CFDNSRecord Decoding

    func testCFDNSRecordDecoding() throws {
        let json = """
        {
            "id": "record-123",
            "type": "A",
            "name": "www.example.com",
            "content": "192.168.1.1",
            "ttl": 300,
            "proxied": true,
            "proxiable": true,
            "priority": null,
            "tags": [],
            "comment": "Web server"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(CFDNSRecord.self, from: data)

        XCTAssertEqual(record.id, "record-123")
        XCTAssertEqual(record.type, "A")
        XCTAssertEqual(record.name, "www.example.com")
        XCTAssertEqual(record.content, "192.168.1.1")
        XCTAssertEqual(record.ttl, 300)
        XCTAssertEqual(record.proxied, true)
        XCTAssertEqual(record.comment, "Web server")
    }

    func testCFDNSRecordWithTimestamps() throws {
        let json = """
        {
            "id": "record-123",
            "type": "A",
            "name": "www.example.com",
            "content": "192.168.1.1",
            "created_on": "2025-10-15T18:55:44.157527Z",
            "modified_on": "2025-10-15T19:00:00Z"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(CFDNSRecord.self, from: data)

        XCTAssertNotNil(record.created_on)
        XCTAssertNotNil(record.modified_on)
    }

    func testCFDNSRecordMinimalFields() throws {
        let json = """
        {
            "id": "record-456",
            "type": "CNAME",
            "name": "blog.example.com",
            "content": "example.com"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(CFDNSRecord.self, from: data)

        XCTAssertEqual(record.id, "record-456")
        XCTAssertNil(record.ttl)
        XCTAssertNil(record.proxied)
        XCTAssertNil(record.priority)
        XCTAssertNil(record.data)
        XCTAssertNil(record.created_on)
        XCTAssertNil(record.modified_on)
    }

    func testCFDNSRecordWithSRVData() throws {
        let json = """
        {
            "id": "record-789",
            "type": "SRV",
            "name": "_sip._tcp.example.com",
            "content": "sip.example.com",
            "data": {
                "service": "_sip",
                "proto": "_tcp",
                "name": "example.com",
                "priority": 10,
                "weight": 5,
                "port": 5060,
                "target": "sip.example.com"
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(CFDNSRecord.self, from: data)

        XCTAssertNotNil(record.data)
        XCTAssertEqual(record.data?.service, "_sip")
        XCTAssertEqual(record.data?.proto, "_tcp")
        XCTAssertEqual(record.data?.port, 5060)
        XCTAssertEqual(record.data?.target, "sip.example.com")
    }

    // MARK: - CFEnvelope Decoding

    func testCFEnvelopeDecoding() throws {
        let json = """
        {
            "success": true,
            "result": [
                {"id": "zone-1", "name": "example.com", "status": "active"}
            ],
            "errors": [],
            "messages": [],
            "result_info": {
                "page": 1,
                "per_page": 50,
                "total_pages": 1,
                "count": 1,
                "total_count": 1
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let envelope = try JSONDecoder().decode(CFEnvelope<[CFZone]>.self, from: data)

        XCTAssertTrue(envelope.success)
        XCTAssertEqual(envelope.result?.count, 1)
        XCTAssertEqual(envelope.result?.first?.name, "example.com")
        XCTAssertTrue(envelope.errors.isEmpty)
    }

    // MARK: - RecordData

    func testRecordDataEncoding() throws {
        let data = RecordData(
            service: "_sip",
            proto: "_tcp",
            name: "example.com",
            priority: 10,
            weight: 5,
            port: 5060,
            target: "sip.example.com",
            flags: nil,
            tag: nil,
            value: nil
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(RecordData.self, from: encoded)

        XCTAssertEqual(decoded.service, "_sip")
        XCTAssertEqual(decoded.proto, "_tcp")
        XCTAssertEqual(decoded.port, 5060)
        XCTAssertEqual(decoded.target, "sip.example.com")
    }

    func testRecordDataCAA() throws {
        let data = RecordData(
            service: nil,
            proto: nil,
            name: nil,
            priority: nil,
            weight: nil,
            port: nil,
            target: nil,
            flags: 0,
            tag: "issue",
            value: "letsencrypt.org"
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(RecordData.self, from: encoded)

        XCTAssertEqual(decoded.flags, 0)
        XCTAssertEqual(decoded.tag, "issue")
        XCTAssertEqual(decoded.value, "letsencrypt.org")
    }

    // MARK: - Route53 Models

    func testR53HostedZoneDecoding() throws {
        let json = """
        {
            "Id": "/hostedzone/Z1234567890",
            "Name": "example.com.",
            "CallerReference": "ref-123",
            "Config": {
                "PrivateZone": false,
                "Comment": "Test zone"
            },
            "ResourceRecordSetCount": 5
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let zone = try JSONDecoder().decode(R53HostedZone.self, from: data)

        XCTAssertEqual(zone.id, "/hostedzone/Z1234567890")
        XCTAssertEqual(zone.name, "example.com.")
        XCTAssertEqual(zone.config?.privateZone, false)
        XCTAssertEqual(zone.config?.comment, "Test zone")
        XCTAssertEqual(zone.resourceRecordSetCount, 5)
    }

    func testR53ResourceRecordSetDecoding() throws {
        let json = """
        {
            "Name": "www.example.com.",
            "Type": "A",
            "TTL": 300,
            "ResourceRecords": [
                {"Value": "192.168.1.1"}
            ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let recordSet = try JSONDecoder().decode(R53ResourceRecordSet.self, from: data)

        XCTAssertEqual(recordSet.name, "www.example.com.")
        XCTAssertEqual(recordSet.type, "A")
        XCTAssertEqual(recordSet.ttl, 300)
        XCTAssertEqual(recordSet.resourceRecords?.count, 1)
        XCTAssertEqual(recordSet.resourceRecords?.first?.value, "192.168.1.1")
    }

    func testR53ResourceRecordSetID() {
        let record = R53ResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            resourceRecords: nil,
            aliasTarget: nil,
            weight: nil,
            region: nil,
            geoLocation: nil,
            failover: nil,
            multiValueAnswer: nil,
            setIdentifier: nil,
            healthCheckId: nil
        )
        XCTAssertEqual(record.id, "www.example.com.|A|")
    }

    func testR53ResourceRecordSetIDWithIdentifier() {
        let record = R53ResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            resourceRecords: nil,
            aliasTarget: nil,
            weight: 70,
            region: nil,
            geoLocation: nil,
            failover: nil,
            multiValueAnswer: nil,
            setIdentifier: "primary",
            healthCheckId: nil
        )
        XCTAssertEqual(record.id, "www.example.com.|A|primary")
    }

    func testR53AliasTargetDecoding() throws {
        let json = """
        {
            "Name": "example.com.",
            "Type": "A",
            "AliasTarget": {
                "DNSName": "d12345.cloudfront.net.",
                "HostedZoneId": "Z2FDTNDATAQYW2",
                "EvaluateTargetHealth": false
            }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let recordSet = try JSONDecoder().decode(R53ResourceRecordSet.self, from: data)

        XCTAssertNotNil(recordSet.aliasTarget)
        XCTAssertEqual(recordSet.aliasTarget?.dnsName, "d12345.cloudfront.net.")
        XCTAssertEqual(recordSet.aliasTarget?.hostedZoneId, "Z2FDTNDATAQYW2")
        XCTAssertEqual(recordSet.aliasTarget?.evaluateTargetHealth, false)
    }

    // MARK: - Vercel Models

    func testVercelDomainDecoding() throws {
        let json = """
        {
            "id": "domain-123",
            "name": "example.com",
            "verified": true,
            "zone": true
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let domain = try JSONDecoder().decode(VercelDomain.self, from: data)

        XCTAssertEqual(domain.id, "domain-123")
        XCTAssertEqual(domain.name, "example.com")
        XCTAssertEqual(domain.verified, true)
    }

    func testVercelDNSRecordDecoding() throws {
        let json = """
        {
            "id": "rec-123",
            "type": "A",
            "name": "www",
            "value": "192.168.1.1",
            "ttl": 300,
            "comment": "Web server"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(VercelDNSRecord.self, from: data)

        XCTAssertEqual(record.id, "rec-123")
        XCTAssertEqual(record.type, "A")
        XCTAssertEqual(record.name, "www")
        XCTAssertEqual(record.value, "192.168.1.1")
        XCTAssertEqual(record.ttl, 300)
    }

    func testVercelDNSRecordWithMX() throws {
        let json = """
        {
            "id": "rec-mx",
            "type": "MX",
            "name": "",
            "value": "mail.example.com",
            "mx": 10,
            "priority": 10
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let record = try JSONDecoder().decode(VercelDNSRecord.self, from: data)

        XCTAssertEqual(record.mx, 10)
        XCTAssertEqual(record.priority, 10)
    }

    // MARK: - Google Cloud Models

    func testGCPManagedZoneDecoding() throws {
        let json = """
        {
            "id": "zone-gcp-123",
            "name": "example-zone",
            "dnsName": "example.com.",
            "description": "Example zone",
            "visibility": "public"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let zone = try JSONDecoder().decode(GCPManagedZone.self, from: data)

        XCTAssertEqual(zone.id, "zone-gcp-123")
        XCTAssertEqual(zone.name, "example-zone")
        XCTAssertEqual(zone.dnsName, "example.com.")
        XCTAssertEqual(zone.dns_name, "example.com.")
        XCTAssertEqual(zone.description, "Example zone")
    }

    func testGCPResourceRecordSetDecoding() throws {
        let json = """
        {
            "name": "www.example.com.",
            "type": "A",
            "ttl": 300,
            "rrdatas": ["192.168.1.1", "192.168.1.2"]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let rrset = try JSONDecoder().decode(GCPResourceRecordSet.self, from: data)

        XCTAssertEqual(rrset.name, "www.example.com.")
        XCTAssertEqual(rrset.type, "A")
        XCTAssertEqual(rrset.ttl, 300)
        XCTAssertEqual(rrset.rrdatas?.count, 2)
    }

    func testGCPResourceRecordSetID() {
        let rrset = GCPResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            rrdatas: ["192.168.1.1"]
        )
        XCTAssertEqual(rrset.id, "www.example.com.-A")
    }

    func testGCPChangeEncoding() throws {
        let addition = GCPResourceRecordSet(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            rrdatas: ["192.168.1.1"]
        )
        let change = GCPChange(additions: [addition], deletions: nil)

        let data = try JSONEncoder().encode(change)
        let decoded = try JSONDecoder().decode(GCPChange.self, from: data)

        XCTAssertEqual(decoded.kind, "dns#change")
        XCTAssertEqual(decoded.additions?.count, 1)
        XCTAssertNil(decoded.deletions)
    }

    // MARK: - CreateR53RecordRequest

    func testCreateR53RecordRequestToResourceRecordSet() {
        let request = CreateR53RecordRequest(
            name: "www.example.com.",
            type: "A",
            ttl: 300,
            values: ["192.168.1.1", "192.168.1.2"],
            weight: nil,
            setIdentifier: nil
        )

        let rrset = request.toResourceRecordSet()

        XCTAssertEqual(rrset.name, "www.example.com.")
        XCTAssertEqual(rrset.type, "A")
        XCTAssertEqual(rrset.ttl, 300)
        XCTAssertEqual(rrset.resourceRecords?.count, 2)
        XCTAssertEqual(rrset.resourceRecords?.first?.value, "192.168.1.1")
    }

    // MARK: - UpdateR53RecordRequest

    func testUpdateR53RecordRequestToResourceRecordSet() {
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

        let request = UpdateR53RecordRequest(
            oldRecord: oldRecord,
            newRecord: R53ResourceRecordSet(
                name: oldRecord.name,
                type: oldRecord.type,
                ttl: 600,
                resourceRecords: [R53ResourceRecord(value: "10.0.0.1")],
                aliasTarget: oldRecord.aliasTarget,
                weight: oldRecord.weight,
                region: oldRecord.region,
                geoLocation: oldRecord.geoLocation,
                failover: oldRecord.failover,
                multiValueAnswer: oldRecord.multiValueAnswer,
                setIdentifier: oldRecord.setIdentifier,
                healthCheckId: oldRecord.healthCheckId
            )
        )

        let rrset = request.newRecord

        XCTAssertEqual(rrset.name, "www.example.com.") // Preserved from old
        XCTAssertEqual(rrset.type, "A") // Preserved from old
        XCTAssertEqual(rrset.ttl, 600) // Updated
        XCTAssertEqual(rrset.resourceRecords?.first?.value, "10.0.0.1") // Updated
    }

    // MARK: - Error Models

    func testVercelErrorDecoding() throws {
        let json = """
        {
            "code": "FORBIDDEN",
            "message": "Access denied"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let error = try JSONDecoder().decode(VercelError.self, from: data)

        XCTAssertEqual(error.code, .forbidden)
        XCTAssertEqual(error.message, "Access denied")
    }

    func testGCPErrorDecoding() throws {
        let json = """
        {
            "code": 403,
            "message": "Permission denied",
            "status": "PERMISSION_DENIED"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let error = try JSONDecoder().decode(GCPError.self, from: data)

        XCTAssertEqual(error.code, 403)
        XCTAssertEqual(error.message, "Permission denied")
        XCTAssertEqual(error.status, "PERMISSION_DENIED")
    }
}
