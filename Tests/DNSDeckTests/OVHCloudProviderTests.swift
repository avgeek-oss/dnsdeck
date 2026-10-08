import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class OVHCloudProviderTests: XCTestCase {
    func testListZonesSynchronizesTimeAndSignsExactRequest() async throws {
        let transport = OVHCloudRecordingTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.url?.absoluteString, "https://eu.api.ovh.com/1.0/auth/time")
                XCTAssertNil(request.value(forHTTPHeaderField: "X-Ovh-Signature"))
                return try Self.response(request: request, status: 200, body: "1700000000")
            }
            XCTAssertEqual(request.url?.absoluteString, "https://eu.api.ovh.com/1.0/domain/zone")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Ovh-Application"), "application")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Ovh-Consumer"), "consumer")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Ovh-Timestamp"), "1700000000")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Ovh-Signature"),
                "$1$ab67a3e9f1fe77196fcdebd1da18599c937cd3c8"
            )
            return try Self.response(request: request, status: 200, body: #"["example.com"]"#)
        }

        let zones = try await makeService(transport: transport).listZones()

        XCTAssertEqual(zones, ["example.com"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testServerTimeDeltaIsCachedAcrossRequests() async throws {
        let transport = OVHCloudRecordingTransport { request, index in
            switch index {
            case 0:
                return try Self.response(request: request, status: 200, body: "1700000000")
            case 1:
                return try Self.response(request: request, status: 200, body: #"["example.com"]"#)
            default:
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Ovh-Timestamp"), "1700000000")
                return try Self.response(request: request, status: 200, body: Self.zoneFixture)
            }
        }
        let service = makeService(transport: transport)

        _ = try await service.listZones()
        _ = try await service.getZone(name: "example.com")

        XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("/auth/time") == true }.count, 1)
    }

    func testRecordListFollowsIDsWithoutConcurrentFanout() async throws {
        let transport = OVHCloudRecordingTransport { request, index in
            switch index {
            case 0:
                return try Self.response(request: request, status: 200, body: "1700000000")
            case 1:
                XCTAssertEqual(request.url?.path, "/1.0/domain/zone/example.com/record")
                return try Self.response(request: request, status: 200, body: "[10,20]")
            default:
                let id = index == 2 ? 10 : 20
                XCTAssertEqual(request.url?.path, "/1.0/domain/zone/example.com/record/\(id)")
                return try Self.response(request: request, status: 200, body: Self.recordFixture(id: id))
            }
        }

        let records = try await makeService(transport: transport).listRecords(zoneName: "example.com")

        XCTAssertEqual(records.map(\.id), [10, 20])
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testCreateZeroIDResolvesNewestMatchingRecord() async throws {
        let transport = OVHCloudRecordingTransport { request, index in
            switch index {
            case 0:
                return try Self.response(request: request, status: 200, body: "1700000000")
            case 1:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(
                    try JSONDecoder().decode(OVHCloudRecordCreate.self, from: XCTUnwrap(request.httpBody)),
                    OVHCloudRecordCreate(fieldType: "A", subDomain: "www", target: "192.0.2.1", ttl: 300)
                )
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"id":0,"zone":"example.com","target":"192.0.2.1","ttl":300,"fieldType":"A","subDomain":"www"}"#
                )
            case 2:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.query, "fieldType=A&subDomain=www")
                return try Self.response(request: request, status: 200, body: "[41,42]")
            case 3:
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"id":42,"zone":"example.com","target":"198.51.100.1","ttl":300,"fieldType":"A","subDomain":"www"}"#
                )
            default:
                return try Self.response(request: request, status: 200, body: Self.recordFixture(id: 41))
            }
        }

        let record = try await makeService(transport: transport).createRecord(
            zoneName: "example.com",
            record: OVHCloudRecordCreate(fieldType: "A", subDomain: "www", target: "192.0.2.1", ttl: 300)
        )

        XCTAssertEqual(record.id, 41)
    }

    func testUpdateDeleteAndRefreshUseDocumentedMethods() async throws {
        let transport = OVHCloudRecordingTransport { request, index in
            if index == 0 { return try Self.response(request: request, status: 200, body: "1700000000") }
            switch index {
            case 1:
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.url?.path, "/1.0/domain/zone/example.com/record/41")
                XCTAssertEqual(
                    try JSONDecoder().decode(OVHCloudRecordUpdate.self, from: XCTUnwrap(request.httpBody)),
                    OVHCloudRecordUpdate(subDomain: "api", target: "192.0.2.2", ttl: 600)
                )
            case 2:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/1.0/domain/zone/example.com/record/41")
            default:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/1.0/domain/zone/example.com/refresh")
            }
            return try Self.response(request: request, status: 200, body: "")
        }
        let service = makeService(transport: transport)

        try await service.updateRecord(
            zoneName: "example.com",
            id: 41,
            record: OVHCloudRecordUpdate(subDomain: "api", target: "192.0.2.2", ttl: 600)
        )
        try await service.deleteRecord(zoneName: "example.com", id: 41)
        try await service.refreshZone(name: "example.com")
    }

    func testMappingsHandleAutomaticTTLTXTAndMX() throws {
        let txt = try CreateProviderRecordRequest(
            name: "@",
            type: "TXT",
            content: #""verification value""#,
            ttl: Constants.TTL.automatic,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toOVHCloudCreate(zoneName: "example.com")
        XCTAssertNil(txt.subDomain)
        XCTAssertEqual(txt.target, "verification value")
        XCTAssertEqual(txt.ttl, 0)

        let mx = try CreateProviderRecordRequest(
            name: "mail.example.com",
            type: "MX",
            content: "mx.example.net.",
            ttl: 300,
            proxied: nil,
            priority: 20,
            comment: nil
        ).toOVHCloudCreate(zoneName: "example.com")
        XCTAssertEqual(mx.subDomain, "mail")
        XCTAssertEqual(mx.target, "20 mx.example.net.")
    }

    func testSnapshotPreservesNativeRecordAndDisplayFields() {
        let record = OVHCloudRecord(
            id: 41,
            zone: "example.com",
            target: "10 mail.example.com.",
            ttl: 0,
            fieldType: "MX",
            subDomain: nil
        )
        let snapshot = record.snapshot()

        XCTAssertEqual(snapshot.name, "@")
        XCTAssertEqual(snapshot.content, "mail.example.com.")
        XCTAssertEqual(snapshot.priority, 10)
        XCTAssertEqual(snapshot.ttl, Constants.TTL.automatic)
        XCTAssertNotNil(snapshot.providerData)
    }

    func testUnknownEndpointFailsBeforeNetwork() async throws {
        let transport = OVHCloudRecordingTransport { _, _ in
            XCTFail("Unknown endpoint must fail before transport")
            throw URLError(.badURL)
        }
        let service = makeService(endpoint: "ovh-ap", transport: transport)

        do {
            _ = try await service.listZones()
            XCTFail("Expected endpoint error")
        } catch let ProviderAPIError.missingCredential(provider, field) {
            XCTAssertEqual(provider, .ovhCloud)
            XCTAssertEqual(field, "API Region")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func makeService(
        endpoint: String = "ovh-eu",
        transport: OVHCloudRecordingTransport
    ) -> OVHCloudService {
        OVHCloudService(
            credentialsProvider: {
                (
                    endpoint: endpoint,
                    applicationKey: "application",
                    applicationSecret: "secret",
                    consumerKey: "consumer"
                )
            },
            transport: transport,
            sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1_700_000_100) }
        )
    }

    private static let zoneFixture = #"{"dnssecSupported":true,"hasDnsAnycast":false,"lastUpdate":"2026-07-10T12:00:00Z","name":"example.com","nameServers":["dns100.ovh.net","ns100.ovh.net"]}"#

    private static func recordFixture(id: Int) -> String {
        #"{"id":\#(id),"zone":"example.com","target":"192.0.2.1","ttl":300,"fieldType":"A","subDomain":"www"}"#
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String
    ) throws -> (Data, URLResponse) {
        try (
            Data(body.utf8),
            XCTUnwrap(
                HTTPURLResponse(
                    url: XCTUnwrap(request.url),
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )
            )
        )
    }
}

@MainActor
private final class OVHCloudRecordingTransport: NetworkTransport {
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
