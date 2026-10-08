import AvgeekNetworking
import Foundation

final class DNSimpleService {
    static let nameservers = [
        "ns1.dnsimple-edge.com",
        "ns2.dnsimple-edge.net",
        "ns3.dnsimple-edge.io",
        "ns4.dnsimple-edge.org",
    ]

    private let accountIdProvider: () -> String?
    private let tokenProvider: () -> String?
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        accountIdProvider: @escaping () -> String?,
        tokenProvider: @escaping () -> String?,
        baseURL: URL = URL(string: Configuration.API.dnsimpleBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        self.accountIdProvider = accountIdProvider
        self.tokenProvider = tokenProvider
        client = ProviderHTTPClient(provider: .dnsimple, baseURL: baseURL, transport: transport, sleep: sleep)
    }

    func listZones() async throws -> [DNSimpleZone] {
        let accountId = try credentials().accountId
        return try await paginate(pathComponents: [accountId, "zones"], type: DNSimpleZone.self)
    }

    func getZone(name: String) async throws -> DNSimpleZone {
        let accountId = try credentials().accountId
        let response = try await authenticatedRequest(
            method: "GET",
            pathComponents: [accountId, "zones", name],
            retryPolicy: .transientRead()
        )
        return try client.decode(DNSimpleSingleEnvelope<DNSimpleZone>.self, from: response).data
    }

    func updateNameservers(domain: String, nameservers: [String]) async throws {
        let accountId = try credentials().accountId
        _ = try await authenticatedRequest(
            method: "PUT",
            pathComponents: [accountId, "registrar", "domains", domain, "delegation"],
            body: encoder.encode(nameservers)
        )
    }

    func nameservers(domain: String) async throws -> [String] {
        let accountId = try credentials().accountId
        let response = try await authenticatedRequest(
            method: "GET",
            pathComponents: [accountId, "registrar", "domains", domain, "delegation"],
            retryPolicy: .transientRead()
        )
        return try client.decode(DNSimpleSingleEnvelope<[String]>.self, from: response).data
    }

    func listRecords(zoneName: String) async throws -> [DNSimpleZoneRecord] {
        let accountId = try credentials().accountId
        return try await paginate(
            pathComponents: [accountId, "zones", zoneName, "records"],
            type: DNSimpleZoneRecord.self
        )
    }

    func createRecord(
        zoneName: String,
        request: DNSimpleRecordCreateRequest
    ) async throws -> DNSimpleZoneRecord {
        let accountId = try credentials().accountId
        let response = try await authenticatedRequest(
            method: "POST",
            pathComponents: [accountId, "zones", zoneName, "records"],
            body: encoder.encode(request)
        )
        return try client.decode(DNSimpleSingleEnvelope<DNSimpleZoneRecord>.self, from: response).data
    }

    func updateRecord(
        zoneName: String,
        recordId: Int,
        request: DNSimpleRecordUpdateRequest
    ) async throws -> DNSimpleZoneRecord {
        let accountId = try credentials().accountId
        let response = try await authenticatedRequest(
            method: "PATCH",
            pathComponents: [accountId, "zones", zoneName, "records", String(recordId)],
            body: encoder.encode(request)
        )
        return try client.decode(DNSimpleSingleEnvelope<DNSimpleZoneRecord>.self, from: response).data
    }

    func deleteRecord(zoneName: String, recordId: Int) async throws {
        let accountId = try credentials().accountId
        _ = try await authenticatedRequest(
            method: "DELETE",
            pathComponents: [accountId, "zones", zoneName, "records", String(recordId)]
        )
    }

    private func paginate<Item: Decodable>(
        pathComponents: [String],
        type: Item.Type
    ) async throws -> [Item] {
        try await client.paginate(from: 1) { page in
            let response = try await authenticatedRequest(
                method: "GET",
                pathComponents: pathComponents,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "per_page", value: "100"),
                ],
                retryPolicy: .transientRead()
            )
            let envelope = try client.decode(DNSimpleCollectionEnvelope<Item>.self, from: response)
            let next = envelope.pagination.currentPage < envelope.pagination.totalPages
                ? envelope.pagination.currentPage + 1
                : nil
            return (envelope.data, next)
        }
    }

    private func credentials() throws -> (accountId: String, token: String) {
        guard let accountId = accountIdProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountId.isEmpty,
              accountId.allSatisfy(\.isNumber)
        else {
            throw ProviderAPIError.missingCredential(provider: .dnsimple, field: "numeric account ID")
        }
        guard let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .dnsimple, field: "account access token")
        }
        return (accountId, token)
    }

    private func authenticatedRequest(
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        let token = try credentials().token
        return try await client.send(
            method: method,
            url: client.url(pathComponents: pathComponents, queryItems: queryItems),
            headers: ["Authorization": "Bearer \(token)"],
            body: body,
            retryPolicy: retryPolicy
        )
    }
}
