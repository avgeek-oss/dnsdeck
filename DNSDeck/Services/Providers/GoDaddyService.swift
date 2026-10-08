import AvgeekNetworking
import Foundation

final class GoDaddyService {
    typealias Credentials = (token: String?, shopperId: String?)

    private let credentialsProvider: () -> Credentials
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        credentialsProvider: @escaping () -> Credentials,
        baseURL: URL = URL(string: Configuration.API.goDaddyBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        self.credentialsProvider = credentialsProvider
        client = ProviderHTTPClient(provider: .goDaddy, baseURL: baseURL, transport: transport, sleep: sleep)
    }

    func listDomains() async throws -> [GoDaddyDomain] {
        try await client.paginate(from: "") { marker in
            var queryItems = [
                URLQueryItem(name: "statuses", value: "ACTIVE"),
                URLQueryItem(name: "statuses", value: "PENDING_DNS_ACTIVE"),
                URLQueryItem(name: "limit", value: "1000"),
                URLQueryItem(name: "includes", value: "nameServers"),
            ]
            if !marker.isEmpty { queryItems.append(URLQueryItem(name: "marker", value: marker)) }
            let response = try await authenticatedRequest(
                method: "GET",
                pathComponents: ["v1", "domains"],
                queryItems: queryItems,
                retryPolicy: .transientRead()
            )
            let page = try client.decode([GoDaddyDomain].self, from: response)
            let candidate = page.count == 1000 ? page.last?.domain : nil
            let next = candidate != marker ? candidate : nil
            return (page, next)
        }
    }

    func getDomain(name: String) async throws -> GoDaddyDomain {
        let response = try await authenticatedRequest(
            method: "GET",
            pathComponents: ["v1", "domains", name],
            retryPolicy: .transientRead()
        )
        return try client.decode(GoDaddyDomain.self, from: response)
    }

    func updateNameservers(domain: String, nameservers: [String]) async throws {
        _ = try await authenticatedRequest(
            method: "PATCH",
            pathComponents: ["v1", "domains", domain],
            body: encoder.encode(GoDaddyNameserverUpdateRequest(nameServers: nameservers))
        )
    }

    func listRecords(domain: String) async throws -> [GoDaddyDNSRecord] {
        try await paginateRecords(pathComponents: ["v1", "domains", domain, "records"])
    }

    func records(domain: String, type: String, name: String) async throws -> [GoDaddyDNSRecord] {
        try await paginateRecords(pathComponents: ["v1", "domains", domain, "records", type, name])
    }

    func addRecords(domain: String, records: [GoDaddyWriteRecord]) async throws {
        _ = try await authenticatedRequest(
            method: "PATCH",
            pathComponents: ["v1", "domains", domain, "records"],
            body: encoder.encode(records)
        )
    }

    func replaceRecords(domain: String, type: String, name: String, records: [GoDaddyWriteRecord]) async throws {
        _ = try await authenticatedRequest(
            method: "PUT",
            pathComponents: ["v1", "domains", domain, "records", type, name],
            body: encoder.encode(records.map { $0.replacingTypeAndName() })
        )
    }

    func deleteRecordSet(domain: String, type: String, name: String) async throws {
        _ = try await authenticatedRequest(
            method: "DELETE",
            pathComponents: ["v1", "domains", domain, "records", type, name]
        )
    }

    private func paginateRecords(pathComponents: [String]) async throws -> [GoDaddyDNSRecord] {
        let limit = 500
        return try await client.paginate(from: 0) { offset in
            let response = try await authenticatedRequest(
                method: "GET",
                pathComponents: pathComponents,
                queryItems: [
                    URLQueryItem(name: "offset", value: String(offset)),
                    URLQueryItem(name: "limit", value: String(limit)),
                ],
                retryPolicy: .transientRead()
            )
            let page = try client.decode([GoDaddyDNSRecord].self, from: response)
            return (page, page.count == limit ? offset + page.count : nil)
        }
    }

    private func authenticatedRequest(
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        let credentials = credentialsProvider()
        guard let token = credentials.token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            throw ProviderAPIError.missingCredential(provider: .goDaddy, field: "Personal Access Token")
        }
        var headers = ["Authorization": "Bearer \(token)"]
        if let shopperId = credentials.shopperId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shopperId.isEmpty
        {
            headers["X-Shopper-Id"] = shopperId
        }
        return try await client.send(
            method: method,
            url: client.url(pathComponents: pathComponents, queryItems: queryItems),
            headers: headers,
            body: body,
            retryPolicy: retryPolicy
        )
    }
}
