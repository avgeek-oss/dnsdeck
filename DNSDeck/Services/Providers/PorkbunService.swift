import AvgeekNetworking
import Foundation

final class PorkbunService {
    typealias Credentials = (apiKey: String?, secretApiKey: String?)

    private let credentialsProvider: () -> Credentials
    private let idempotencyKeyProvider: () -> String
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        credentialsProvider: @escaping () -> Credentials,
        baseURL: URL = URL(string: Configuration.API.porkbunBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep,
        idempotencyKeyProvider: @escaping () -> String = { UUID().uuidString }
    ) {
        self.credentialsProvider = credentialsProvider
        self.idempotencyKeyProvider = idempotencyKeyProvider
        client = ProviderHTTPClient(provider: .porkbun, baseURL: baseURL, transport: transport, sleep: sleep)
    }

    func listDomains() async throws -> [PorkbunDomain] {
        try await client.paginate(from: 0) { start in
            let response = try await read(
                pathComponents: ["domain", "listAll"],
                queryItems: [
                    URLQueryItem(name: "start", value: String(start)),
                    URLQueryItem(name: "sortName", value: "domain"),
                    URLQueryItem(name: "sortDirection", value: "asc"),
                ]
            )
            let page = try decode(PorkbunDomainListResponse.self, from: response)
            var manageableDomains: [(index: Int, domain: PorkbunDomain)] = []
            var externalDomains: [(index: Int, domain: PorkbunDomain)] = []
            for (index, domain) in page.domains.enumerated() {
                if domain.apiAccess?.value == 1 {
                    manageableDomains.append((index, domain))
                } else if domain.notLocal?.value == 1 {
                    externalDomains.append((index, domain))
                }
            }
            manageableDomains += await verifiedExternalDNSDomains(externalDomains)
            return (
                manageableDomains.sorted { $0.index < $1.index }.map(\.domain),
                page.domains.count == 1000 ? start + page.domains.count : nil
            )
        }
    }

    private func verifiedExternalDNSDomains(
        _ domains: [(index: Int, domain: PorkbunDomain)]
    ) async -> [(index: Int, domain: PorkbunDomain)] {
        await withTaskGroup(of: (Int, PorkbunDomain?).self) { group in
            var iterator = domains.makeIterator()
            var verifiedDomains: [(index: Int, domain: PorkbunDomain)] = []

            for _ in 0 ..< min(4, domains.count) {
                guard let entry = iterator.next() else { break }
                group.addTask { [weak self] in
                    let domain = await self?.verifiedExternalDNSDomain(entry.domain)
                    return (entry.index, domain)
                }
            }

            while let (index, domain) = await group.next() {
                if let domain {
                    verifiedDomains.append((index, domain))
                }
                if let entry = iterator.next() {
                    group.addTask { [weak self] in
                        let domain = await self?.verifiedExternalDNSDomain(entry.domain)
                        return (entry.index, domain)
                    }
                }
            }

            return verifiedDomains
        }
    }

    private func verifiedExternalDNSDomain(_ domain: PorkbunDomain) async -> PorkbunDomain? {
        // `listAll` reports API access as disabled for Porkbun Free DNS zones,
        // while the single-domain endpoint returns their effective access state.
        guard let details = try? await getDomain(name: domain.domain) else { return nil }
        return details.apiAccess?.value == 1 ? details : nil
    }

    func getDomain(name: String) async throws -> PorkbunDomain {
        let response = try await read(pathComponents: ["domain", "get", name])
        return try decode(PorkbunDomainResponse.self, from: response).domain
    }

    func nameservers(domain: String) async throws -> [String] {
        let response = try await read(pathComponents: ["domain", "getNs", domain])
        return try decode(PorkbunNameserverResponse.self, from: response).ns
    }

    func updateNameservers(domain: String, nameservers: [String]) async throws {
        let credentials = try credentials()
        let response = try await write(
            pathComponents: ["domain", "updateNs", domain],
            body: encoder.encode(
                PorkbunNameserverUpdateRequest(
                    apiKey: credentials.apiKey,
                    secretApiKey: credentials.secretApiKey,
                    nameservers: nameservers
                )
            )
        )
        try ensureSuccess(response)
    }

    func listRecords(domain: String) async throws -> PorkbunDNSRecordsResponse {
        let response = try await read(pathComponents: ["dns", "retrieve", domain])
        return try decode(PorkbunDNSRecordsResponse.self, from: response)
    }

    func createRecord(domain: String, request: PorkbunDNSWriteRequest) async throws -> String {
        let credentials = try credentials()
        let response = try await write(
            pathComponents: ["dns", "create", domain],
            body: encoder.encode(
                request.authenticated(apiKey: credentials.apiKey, secretApiKey: credentials.secretApiKey)
            )
        )
        return try decode(PorkbunCreateDNSResponse.self, from: response).id.value
    }

    func updateRecord(domain: String, recordId: String, request: PorkbunDNSWriteRequest) async throws {
        let credentials = try credentials()
        let response = try await write(
            pathComponents: ["dns", "edit", domain, recordId],
            body: encoder.encode(
                request.authenticated(apiKey: credentials.apiKey, secretApiKey: credentials.secretApiKey)
            )
        )
        try ensureSuccess(response)
    }

    func deleteRecord(domain: String, recordId: String) async throws {
        let credentials = try credentials()
        let response = try await write(
            pathComponents: ["dns", "delete", domain, recordId],
            body: encoder.encode(
                PorkbunAuthRequest(apiKey: credentials.apiKey, secretApiKey: credentials.secretApiKey)
            )
        )
        try ensureSuccess(response)
    }

    private func read(
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) async throws -> ProviderHTTPResponse {
        let credentials = try credentials()
        return try await client.send(
            method: "GET",
            url: client.url(pathComponents: pathComponents, queryItems: queryItems),
            headers: [
                "X-API-Key": credentials.apiKey,
                "X-Secret-API-Key": credentials.secretApiKey,
            ],
            retryPolicy: .transientRead()
        )
    }

    private func write(pathComponents: [String], body: Data) async throws -> ProviderHTTPResponse {
        try await client.send(
            method: "POST",
            url: client.url(pathComponents: pathComponents),
            headers: ["Idempotency-Key": idempotencyKeyProvider()],
            body: body,
            retryPolicy: .idempotentWrite()
        )
    }

    private func decode<Response: Decodable>(
        _ type: Response.Type,
        from response: ProviderHTTPResponse
    ) throws -> Response {
        try ensureSuccess(response)
        return try client.decode(type, from: response)
    }

    private func ensureSuccess(_ response: ProviderHTTPResponse) throws {
        let status = try client.decode(PorkbunStatusEnvelope.self, from: response)
        guard status.status.uppercased() == "SUCCESS" else {
            throw ProviderAPIError.http(
                provider: .porkbun,
                statusCode: response.response.statusCode,
                message: status.resolvedMessage,
                requestId: status.requestId ?? response.response.value(forHTTPHeaderField: "X-Request-Id"),
                retryAfter: nil
            )
        }
    }

    private func credentials() throws -> (apiKey: String, secretApiKey: String) {
        let credentials = credentialsProvider()
        guard let apiKey = credentials.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .porkbun, field: "API Key")
        }
        guard let secretApiKey = credentials.secretApiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secretApiKey.isEmpty
        else {
            throw ProviderAPIError.missingCredential(provider: .porkbun, field: "Secret API Key")
        }
        return (apiKey, secretApiKey)
    }
}
