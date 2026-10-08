import AvgeekNetworking
import Foundation

final class ScalewayService {
    typealias Credentials = (secretKey: String?, projectId: String?)

    private let credentialsProvider: () -> Credentials
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        credentialsProvider: @escaping () -> Credentials,
        baseURL: URL = URL(string: Configuration.API.scalewayBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        self.credentialsProvider = credentialsProvider
        client = ProviderHTTPClient(provider: .scaleway, baseURL: baseURL, transport: transport, sleep: sleep)
    }

    func listZones() async throws -> [ScalewayDNSZone] {
        let credentials = try credentials()
        var zoneCount = 0
        return try await client.paginate(from: 1) { page in
            let response = try await request(
                credentials: credentials,
                method: "GET",
                pathComponents: ["dns-zones"],
                queryItems: [
                    URLQueryItem(name: "project_id", value: credentials.projectId),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page_size", value: "100"),
                ],
                retryPolicy: .transientRead()
            )
            let result = try client.decode(ScalewayListZonesResponse.self, from: response)
            zoneCount += result.dnsZones.count
            let next = zoneCount < result.totalCount && !result.dnsZones.isEmpty ? page + 1 : nil
            return (result.dnsZones, next)
        }
    }

    func getZone(name: String) async throws -> ScalewayDNSZone {
        let zones = try await listZones()
        guard let zone = zones.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ProviderAPIError.operationFailed(
                provider: .scaleway,
                operation: "zone lookup",
                message: "Zone not found"
            )
        }
        return zone
    }

    func deleteZone(name: String) async throws {
        let credentials = try credentials()
        _ = try await request(
            credentials: credentials,
            method: "DELETE",
            pathComponents: ["dns-zones", name],
            queryItems: [URLQueryItem(name: "project_id", value: credentials.projectId)]
        )
    }

    func updateNameservers(zoneName: String, nameservers: [String]) async throws {
        let credentials = try credentials()
        _ = try await request(
            credentials: credentials,
            method: "PUT",
            pathComponents: ["dns-zones", zoneName, "nameservers"],
            body: encoder.encode(
                ScalewayNameserverUpdateRequest(
                    nameservers: nameservers.map { ScalewayNameserver(name: $0, ip: []) }
                )
            ),
            retryPolicy: .idempotentWrite()
        )
    }

    func listRecords(zoneName: String) async throws -> [ScalewayRecord] {
        let credentials = try credentials()
        var recordCount = 0
        return try await client.paginate(from: 1) { page in
            let response = try await request(
                credentials: credentials,
                method: "GET",
                pathComponents: ["dns-zones", zoneName, "records"],
                queryItems: [
                    URLQueryItem(name: "project_id", value: credentials.projectId),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page_size", value: "100"),
                ],
                retryPolicy: .transientRead()
            )
            let result = try client.decode(ScalewayListRecordsResponse.self, from: response)
            recordCount += result.records.count
            let next = recordCount < result.totalCount && !result.records.isEmpty ? page + 1 : nil
            return (result.records, next)
        }
    }

    func apply(zoneName: String, changes: [ScalewayRecordChange]) async throws {
        let credentials = try credentials()
        _ = try await request(
            credentials: credentials,
            method: "PATCH",
            pathComponents: ["dns-zones", zoneName, "records"],
            body: encoder.encode(
                ScalewayUpdateRecordsRequest(
                    changes: changes,
                    returnAllRecords: false,
                    disallowNewZoneCreation: true
                )
            )
        )
    }

    private func credentials() throws -> (secretKey: String, projectId: String) {
        let value = credentialsProvider()
        guard let secretKey = value.secretKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secretKey.isEmpty
        else {
            throw ProviderAPIError.missingCredential(provider: .scaleway, field: "Secret Key")
        }
        guard let projectId = value.projectId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectId.isEmpty
        else {
            throw ProviderAPIError.missingCredential(provider: .scaleway, field: "Project ID")
        }
        return (secretKey, projectId)
    }

    private func request(
        credentials: (secretKey: String, projectId: String),
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        try await client.send(
            method: method,
            url: client.url(pathComponents: pathComponents, queryItems: queryItems),
            headers: ["X-Auth-Token": credentials.secretKey],
            body: body,
            retryPolicy: retryPolicy
        )
    }
}
