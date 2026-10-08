import AvgeekNetworking
import XCTest
@testable import DNSDeckMCP

@MainActor
final class HetznerProviderTests: XCTestCase {
    func testListZonesUsesDocumentedPaginationAndBearerAuthentication() async throws {
        let transport = HetznerRecordingTransport { request, index in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hetzner-token")
            XCTAssertEqual(request.url?.path, "/v1/zones")

            if index == 0 {
                XCTAssertEqual(request.url?.query, "page=1&per_page=50")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"zones":[{"id":42,"name":"one.example"}],"meta":{"pagination":{"page":1,"next_page":2,"last_page":2}}}"#
                )
            }

            XCTAssertEqual(request.url?.query, "page=2&per_page=50")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"zones":[{"id":43,"name":"two.example"}],"meta":{"pagination":{"page":2,"next_page":null,"last_page":2}}}"#
            )
        }
        let service = makeService(transport: transport)

        let zones = try await service.listZones()

        XCTAssertEqual(zones.map(\.id), [42, 43])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testCreateZoneWaitsForActionAndReloadsAssignedNameservers() async throws {
        var delays: [TimeInterval] = []
        let transport = HetznerRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/zones")
                XCTAssertEqual(
                    try JSONDecoder().decode(HetznerCreateZoneRequest.self, from: XCTUnwrap(request.httpBody)),
                    HetznerCreateZoneRequest(name: "example.com", mode: "primary", ttl: 3600)
                )
                return try Self.response(
                    request: request,
                    status: 201,
                    body: #"{"zone":{"id":42,"name":"example.com"},"action":{"id":14,"status":"running"}}"#
                )
            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/actions/14")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"action":{"id":14,"status":"success"}}"#
                )
            default:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/zones/42")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"zone":{"id":42,"name":"example.com","ttl":3600,"mode":"primary","status":"ok","authoritative_nameservers":{"assigned":["hydrogen.ns.hetzner.com.","oxygen.ns.hetzner.com.","helium.ns.hetzner.de."],"delegated":[],"delegation_last_check":null,"delegation_status":"unregistered"}}}"#
                )
            }
        }
        let service = makeService(transport: transport) { delays.append($0) }

        let zone = try await service.createZone(name: "example.com")

        XCTAssertEqual(zone.authoritativeNameservers?.assigned.count, 3)
        XCTAssertEqual(delays, [0.5])
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testListRRSetsPreservesValuesCommentsAndNativeData() async throws {
        let transport = HetznerRecordingTransport { request, _ in
            XCTAssertEqual(request.url?.path, "/v1/zones/42/rrsets")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"rrsets":[{"zone":42,"id":"@/TXT","name":"@","type":"TXT","ttl":null,"labels":{},"protection":{"change":false},"records":[{"value":"\"hello \" \"world\"","comment":"verification"}]}],"meta":{"pagination":{"page":1,"next_page":null,"last_page":1}}}"#
            )
        }
        let service = makeService(transport: transport)

        let rrsets = try await service.listRRSets(zoneIdOrName: "42")
        let rrset = try XCTUnwrap(rrsets.first)
        let snapshot = rrset.snapshot()

        XCTAssertEqual(snapshot.values, ["hello world"])
        XCTAssertEqual(snapshot.comment, "verification")
        XCTAssertNil(snapshot.ttl)
        XCTAssertNotNil(snapshot.providerData)
    }

    func testCreateUpdateAndDeleteRRSetContracts() async throws {
        let original = HetznerRRSet(
            id: "www/A",
            name: "www",
            type: "A",
            ttl: nil,
            labels: [:],
            protection: .init(change: false),
            records: [HetznerRRSetRecord(value: "198.51.100.1", comment: "old")],
            zone: 42
        )
        let createRequest = HetznerCreateRRSetRequest(
            name: "www",
            type: "A",
            ttl: nil,
            records: [HetznerRRSetRecord(value: "198.51.100.1", comment: "web")]
        )
        let desired = HetznerRRSetDesiredState(
            name: "www",
            type: "A",
            ttl: 3600,
            labels: [:],
            records: [HetznerRRSetRecord(value: "198.51.100.2", comment: "new")],
            identityChanged: false,
            recordsChanged: true,
            ttlChanged: true
        )
        let transport = HetznerRecordingTransport { request, index in
            switch index {
            case 0:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/zones/42/rrsets")
                XCTAssertEqual(
                    try JSONDecoder().decode(HetznerCreateRRSetRequest.self, from: XCTUnwrap(request.httpBody)),
                    createRequest
                )
                return try Self.response(
                    request: request,
                    status: 201,
                    body: #"{"rrset":{"zone":42,"id":"www/A","name":"www","type":"A","ttl":null,"records":[{"value":"198.51.100.1","comment":"web"}]},"action":{"id":1,"status":"success"}}"#
                )
            case 1:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/zones/42/rrsets/www/A/actions/set_records")
                XCTAssertEqual(
                    try JSONDecoder().decode(HetznerSetRecordsRequest.self, from: XCTUnwrap(request.httpBody)),
                    HetznerSetRecordsRequest(records: desired.records)
                )
                return try Self.response(
                    request: request,
                    status: 201,
                    body: #"{"action":{"id":2,"status":"success"}}"#
                )
            case 2:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/zones/42/rrsets/www/A/actions/change_ttl")
                XCTAssertEqual(
                    try JSONDecoder().decode(HetznerChangeTTLRequest.self, from: XCTUnwrap(request.httpBody)),
                    HetznerChangeTTLRequest(ttl: 3600)
                )
                return try Self.response(
                    request: request,
                    status: 201,
                    body: #"{"action":{"id":3,"status":"success"}}"#
                )
            case 3 ... 5:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/zones/42/rrsets")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"rrsets":[{"zone":42,"id":"www/A","name":"www","type":"A","ttl":3600,"records":[{"value":"198.51.100.2","comment":"new"}]}]}"#
                )
            case 6:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v1/zones/42/rrsets/www/A")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"action":{"id":4,"status":"success"}}"#
                )
            default:
                XCTAssertEqual(request.httpMethod, "GET")
                return try Self.response(request: request, status: 200, body: #"{"rrsets":[]}"#)
            }
        }
        let service = makeService(transport: transport)

        _ = try await service.createRRSet(zoneIdOrName: "42", request: createRequest)
        try await service.updateRRSet(zoneIdOrName: "42", existing: original, desired: desired)
        try await service.deleteRRSet(zoneIdOrName: "42", rrset: original)

        XCTAssertEqual(transport.requests.count, 10)
    }

    func testRenameCreatesReplacementBeforeDeletingOriginal() async throws {
        let original = HetznerRRSet(
            id: "www/A",
            name: "www",
            type: "A",
            ttl: 3600,
            labels: [:],
            protection: .init(change: false),
            records: [HetznerRRSetRecord(value: "198.51.100.1")],
            zone: 42
        )
        let desired = UpdateProviderRecordRequest(name: "api")
            .toHetznerState(zoneName: "example.com", existing: original)
        let transport = HetznerRecordingTransport { request, index in
            if index == 0 {
                XCTAssertEqual(request.httpMethod, "POST")
                let body = try JSONDecoder().decode(
                    HetznerCreateRRSetRequest.self,
                    from: XCTUnwrap(request.httpBody)
                )
                XCTAssertEqual(body.name, "api")
                XCTAssertEqual(body.records, original.records)
                return try Self.response(
                    request: request,
                    status: 201,
                    body: #"{"rrset":{"zone":42,"id":"api/A","name":"api","type":"A","ttl":3600,"records":[{"value":"198.51.100.1"}]},"action":{"id":1,"status":"success"}}"#
                )
            }
            if (2 ... 4).contains(index) {
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v1/zones/42/rrsets")
                return try Self.response(
                    request: request,
                    status: 200,
                    body: #"{"rrsets":[{"zone":42,"id":"api/A","name":"api","type":"A","ttl":3600,"records":[{"value":"198.51.100.1"}]}]}"#
                )
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v1/zones/42/rrsets/www/A")
            return try Self.response(
                request: request,
                status: 200,
                body: #"{"action":{"id":2,"status":"success"}}"#
            )
        }
        let service = makeService(transport: transport)

        try await service.updateRRSet(zoneIdOrName: "42", existing: original, desired: desired)

        XCTAssertTrue(desired.identityChanged)
        XCTAssertEqual(transport.requests.count, 5)
    }

    func testRequestMappingSupportsInheritedTTLStructuredMXAndTXTFormatting() throws {
        let mx = CreateProviderRecordRequest(
            name: "mail.example.com",
            type: "MX",
            content: "mx.example.com.",
            ttl: 1,
            proxied: nil,
            priority: 20,
            comment: "primary"
        ).toHetznerRequest(zoneName: "example.com")
        XCTAssertEqual(mx.name, "mail")
        XCTAssertNil(mx.ttl)
        XCTAssertEqual(mx.records, [HetznerRRSetRecord(value: "20 mx.example.com.", comment: "primary")])

        let longTXT = String(repeating: "a", count: 260)
        let txt = CreateProviderRecordRequest(
            name: "@",
            type: "TXT",
            content: longTXT,
            ttl: 3600,
            proxied: nil,
            priority: nil,
            comment: nil
        ).toHetznerRequest(zoneName: "example.com")
        XCTAssertTrue(txt.records[0].value.hasPrefix("\""))
        XCTAssertTrue(txt.records[0].value.contains("\" \""))
        XCTAssertEqual(txt.records[0].value.filter { $0 == "a" }.count, 260)

        let unsetTTLData = try JSONEncoder().encode(HetznerChangeTTLRequest(ttl: nil))
        let unsetTTL = try XCTUnwrap(JSONSerialization.jsonObject(with: unsetTTLData) as? [String: Any])
        XCTAssertTrue(unsetTTL["ttl"] is NSNull)
    }

    func testActionFailureIsSurfacedWithActionContext() async throws {
        let transport = HetznerRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 201,
                body: #"{"rrset":{"zone":42,"id":"www/A","name":"www","type":"A","records":[{"value":"198.51.100.1"}]},"action":{"id":99,"status":"error","error":{"code":"invalid_input","message":"invalid record"}}}"#
            )
        }
        let service = makeService(transport: transport)
        let request = HetznerCreateRRSetRequest(
            name: "www",
            type: "A",
            ttl: 3600,
            records: [HetznerRRSetRecord(value: "198.51.100.1")]
        )

        do {
            _ = try await service.createRRSet(zoneIdOrName: "42", request: request)
            XCTFail("Expected action failure")
        } catch let ProviderAPIError.actionFailed(provider, actionId, code, message) {
            XCTAssertEqual(provider, .hetzner)
            XCTAssertEqual(actionId, 99)
            XCTAssertEqual(code, "invalid_input")
            XCTAssertEqual(message, "invalid record")
        }
    }

    func testErrorEnvelopeUsesCorrelationID() async throws {
        let transport = HetznerRecordingTransport { request, _ in
            try Self.response(
                request: request,
                status: 401,
                body: #"{"error":{"code":"unauthorized","message":"invalid token"}}"#,
                headers: ["X-Correlation-Id": "correlation-42"]
            )
        }
        let service = makeService(transport: transport)

        do {
            _ = try await service.listZones()
            XCTFail("Expected authentication error")
        } catch let ProviderAPIError.http(provider, statusCode, message, requestId, _) {
            XCTAssertEqual(provider, .hetzner)
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "invalid token")
            XCTAssertEqual(requestId, "correlation-42")
        }
    }

    private func makeService(
        transport: HetznerRecordingTransport,
        sleep: @escaping ProviderHTTPClient.Sleep = { _ in }
    ) -> HetznerService {
        HetznerService(
            tokenProvider: { "hetzner-token" },
            baseURL: URL(string: "https://api.hetzner.test/v1")!,
            transport: transport,
            sleep: sleep
        )
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) throws -> (Data, URLResponse) {
        var responseHeaders = ["Content-Type": "application/json"]
        responseHeaders.merge(headers) { _, new in new }
        return try (
            Data(body.utf8),
            XCTUnwrap(
                try HTTPURLResponse(
                    url: XCTUnwrap(request.url),
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: responseHeaders
                )
            )
        )
    }
}

@MainActor
private final class HetznerRecordingTransport: NetworkTransport {
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
