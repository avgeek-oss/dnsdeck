import AvgeekNetworking
import Foundation

final class PowerDNSService {
    typealias Credentials = (endpoint: String?, apiKey: String?, serverId: String?, nameserver: String?)

    private struct Connection {
        let client: ProviderHTTPClient
        let apiKey: String
        let serverId: String
        let nameserver: String?
    }

    private let credentialsProvider: () -> Credentials
    private let transport: any NetworkTransport
    private let sleep: ProviderHTTPClient.Sleep
    private let encoder = JSONEncoder()

    init(
        credentialsProvider: @escaping () -> Credentials,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        self.credentialsProvider = credentialsProvider
        self.transport = transport
        self.sleep = sleep
    }

    func listZones() async throws -> [PowerDNSZone] {
        let connection = try connection()
        let response = try await request(
            connection: connection,
            method: "GET",
            pathComponents: ["servers", connection.serverId, "zones"],
            retryPolicy: .transientRead()
        )
        return try connection.client.decode([PowerDNSZone].self, from: response)
    }

    func getZone(id: String) async throws -> PowerDNSZone {
        let connection = try connection()
        let response = try await request(
            connection: connection,
            method: "GET",
            pathComponents: ["servers", connection.serverId, "zones", id],
            queryItems: [
                URLQueryItem(name: "rrsets", value: "true"),
                URLQueryItem(name: "include_disabled", value: "true"),
            ],
            retryPolicy: .transientRead()
        )
        return try connection.client.decode(PowerDNSZone.self, from: response)
    }

    func createZone(name: String) async throws -> PowerDNSZone {
        let connection = try connection()
        let normalizedName = name.hasSuffix(".") ? name : "\(name)."
        let nameservers = connection.nameserver.map { value in
            [value.hasSuffix(".") ? value : "\(value)."]
        } ?? []
        let response = try await request(
            connection: connection,
            method: "POST",
            pathComponents: ["servers", connection.serverId, "zones"],
            body: encoder.encode(
                PowerDNSCreateZoneRequest(
                    name: normalizedName,
                    kind: "Native",
                    masters: [],
                    nameservers: nameservers
                )
            )
        )
        return try connection.client.decode(PowerDNSZone.self, from: response)
    }

    func deleteZone(id: String) async throws {
        let connection = try connection()
        _ = try await request(
            connection: connection,
            method: "DELETE",
            pathComponents: ["servers", connection.serverId, "zones", id]
        )
    }

    func patchZone(id: String, changes: [PowerDNSRRsetChange]) async throws {
        let connection = try connection()
        _ = try await request(
            connection: connection,
            method: "PATCH",
            pathComponents: ["servers", connection.serverId, "zones", id],
            body: encoder.encode(PowerDNSZonePatch(rrsets: changes))
        )
    }

    private func connection() throws -> Connection {
        let credentials = credentialsProvider()
        guard let endpoint = credentials.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !endpoint.isEmpty
        else {
            throw ProviderAPIError.missingCredential(provider: .powerDNS, field: "API Endpoint")
        }
        guard let apiKey = credentials.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .powerDNS, field: "API Key")
        }
        let baseURL = try normalizedEndpoint(endpoint)
        return Connection(
            client: ProviderHTTPClient(
                provider: .powerDNS,
                baseURL: baseURL,
                transport: transport,
                sleep: sleep
            ),
            apiKey: apiKey,
            serverId: credentials.serverId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "localhost",
            nameserver: credentials.nameserver?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private func normalizedEndpoint(_ value: String) throws -> URL {
        guard var components = URLComponents(string: value),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let host = components.host?.lowercased()
        else {
            throw ProviderAPIError.invalidURL(provider: .powerDNS)
        }
        let scheme = components.scheme?.lowercased()
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLoopback) else {
            throw ProviderAPIError.invalidURL(provider: .powerDNS)
        }
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if !path.lowercased().hasSuffix("/api/v1") { path.append("/api/v1") }
        components.path = path
        guard let url = components.url else { throw ProviderAPIError.invalidURL(provider: .powerDNS) }
        return url
    }

    private func request(
        connection: Connection,
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        try await connection.client.send(
            method: method,
            url: connection.client.url(pathComponents: pathComponents, queryItems: queryItems),
            headers: ["X-API-Key": connection.apiKey],
            body: body,
            retryPolicy: retryPolicy
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
