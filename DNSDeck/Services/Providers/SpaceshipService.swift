import AvgeekNetworking
import Foundation

final class SpaceshipService {
    typealias Credentials = (apiKey: String?, apiSecret: String?)

    private let credentialsProvider: () -> Credentials
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        credentialsProvider: @escaping () -> Credentials,
        baseURL: URL = URL(string: Configuration.API.spaceshipBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep,
        now: @escaping () -> Date = Date.init
    ) {
        self.credentialsProvider = credentialsProvider
        client = ProviderHTTPClient(
            provider: .spaceship,
            baseURL: baseURL,
            transport: transport,
            sleep: sleep,
            now: now
        )
    }

    func listDomains() async throws -> [SpaceshipDomain] {
        try await paginate(pathComponents: ["v1", "domains"], pageSize: 100, response: SpaceshipDomainListResponse.self)
    }

    func getDomain(name: String) async throws -> SpaceshipDomain {
        let response = try await request(
            method: "GET",
            pathComponents: ["v1", "domains", name],
            retryPolicy: .transientRead()
        )
        return try client.decode(SpaceshipDomain.self, from: response)
    }

    func updateNameservers(domain: String, nameservers: [String]) async throws {
        _ = try await request(
            method: "PUT",
            pathComponents: ["v1", "domains", domain, "nameservers"],
            body: encoder.encode(SpaceshipNameserverUpdateRequest(provider: "custom", hosts: nameservers)),
            retryPolicy: .idempotentWrite()
        )
    }

    func listRecords(domain: String) async throws -> [SpaceshipDNSRecord] {
        try await paginate(
            pathComponents: ["v1", "dns", "records", domain],
            pageSize: 500,
            response: SpaceshipRecordListResponse.self
        )
    }

    func saveRecords(domain: String, records: [SpaceshipRecordMutation]) async throws {
        for records in records.batches(of: 500) {
            _ = try await request(
                method: "PUT",
                pathComponents: ["v1", "dns", "records", domain],
                body: encoder.encode(SpaceshipSaveRecordsRequest(force: false, items: records)),
                retryPolicy: .idempotentWrite()
            )
        }
    }

    func deleteRecords(domain: String, records: [SpaceshipRecordMutation]) async throws {
        for records in records.batches(of: 500) {
            _ = try await request(
                method: "DELETE",
                pathComponents: ["v1", "dns", "records", domain],
                body: encoder.encode(records.map { $0.replacingTTL(nil) }),
                retryPolicy: .idempotentWrite()
            )
        }
    }

    private func paginate<Response: SpaceshipPaginatedResponse>(
        pathComponents: [String],
        pageSize: Int,
        response: Response.Type
    ) async throws -> [Response.Item] {
        try await client.paginate(from: 0) { skip in
            let result = try await request(
                method: "GET",
                pathComponents: pathComponents,
                queryItems: [
                    URLQueryItem(name: "take", value: String(pageSize)),
                    URLQueryItem(name: "skip", value: String(skip)),
                    URLQueryItem(name: "orderBy", value: "name"),
                ],
                retryPolicy: .transientRead()
            )
            let page = try client.decode(response, from: result)
            let values = page.pageItems
            guard skip + values.count >= page.total || !values.isEmpty else {
                throw ProviderAPIError.invalidURL(provider: .spaceship)
            }
            return (values, skip + values.count < page.total ? skip + values.count : nil)
        }
    }

    private func request(
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        let credentials = try credentials()
        return try await client.send(
            method: method,
            url: client.url(pathComponents: pathComponents, queryItems: queryItems),
            headers: [
                "X-API-Key": credentials.apiKey,
                "X-API-Secret": credentials.apiSecret,
            ],
            body: body,
            retryPolicy: retryPolicy
        )
    }

    private func credentials() throws -> (apiKey: String, apiSecret: String) {
        let credentials = credentialsProvider()
        guard let apiKey = credentials.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .spaceship, field: "API key")
        }
        guard let apiSecret = credentials.apiSecret?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiSecret.isEmpty
        else {
            throw ProviderAPIError.missingCredential(provider: .spaceship, field: "API secret")
        }
        return (apiKey, apiSecret)
    }
}

private extension Array {
    func batches(of size: Int) -> [[Element]] {
        guard !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start ..< Swift.min(start + size, count)])
        }
    }
}

private protocol SpaceshipPaginatedResponse: Decodable {
    associatedtype Item
    var pageItems: [Item] { get }
    var total: Int { get }
}

extension SpaceshipDomainListResponse: SpaceshipPaginatedResponse {
    fileprivate var pageItems: [SpaceshipDomain] {
        items
    }
}

extension SpaceshipRecordListResponse: SpaceshipPaginatedResponse {
    fileprivate var pageItems: [SpaceshipDNSRecord] {
        items
    }
}
