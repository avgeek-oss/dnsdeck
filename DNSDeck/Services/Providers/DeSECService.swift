import AvgeekNetworking
import Foundation

final class DeSECService {
    private let tokenProvider: () -> String?
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        tokenProvider: @escaping () -> String?,
        baseURL: URL = URL(string: Configuration.API.deSECBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        self.tokenProvider = tokenProvider
        client = ProviderHTTPClient(provider: .deSEC, baseURL: baseURL, transport: transport, sleep: sleep)
    }

    func listDomains() async throws -> [DeSECDomain] {
        try await paginate(pathComponents: ["domains"], type: DeSECDomain.self)
    }

    func getDomain(name: String) async throws -> DeSECDomain {
        let response = try await authenticatedRequest(
            method: "GET",
            pathComponents: ["domains", name],
            retryPolicy: .transientRead()
        )
        return try client.decode(DeSECDomain.self, from: response)
    }

    func createDomain(name: String) async throws -> DeSECDomain {
        let response = try await authenticatedRequest(
            method: "POST",
            pathComponents: ["domains"],
            body: encoder.encode(DeSECCreateDomainRequest(name: name))
        )
        return try client.decode(DeSECDomain.self, from: response)
    }

    func deleteDomain(name: String) async throws {
        _ = try await authenticatedRequest(method: "DELETE", pathComponents: ["domains", name])
    }

    func listRRsets(domain: String) async throws -> [DeSECRRset] {
        try await paginate(pathComponents: ["domains", domain, "rrsets"], type: DeSECRRset.self)
    }

    func createRRset(domain: String, request: DeSECRRsetWriteRequest) async throws {
        _ = try await authenticatedRequest(
            method: "POST",
            pathComponents: ["domains", domain, "rrsets"],
            body: encoder.encode(request),
            retryPolicy: .transientResponseWrite()
        )
    }

    func createRRsets(domain: String, requests: [DeSECRRsetWriteRequest]) async throws {
        guard !requests.isEmpty else { return }
        _ = try await authenticatedRequest(
            method: "POST",
            pathComponents: ["domains", domain, "rrsets"],
            body: encoder.encode(requests),
            retryPolicy: .transientResponseWrite()
        )
    }

    func replaceRRset(domain: String, request: DeSECRRsetWriteRequest) async throws {
        _ = try await authenticatedRequest(
            method: "PUT",
            pathComponents: rrsetPath(domain: domain, subname: request.subname, type: request.type),
            body: encoder.encode(request),
            retryPolicy: .idempotentWrite()
        )
    }

    func deleteRRset(domain: String, subname: String, type: String) async throws {
        _ = try await authenticatedRequest(
            method: "DELETE",
            pathComponents: rrsetPath(domain: domain, subname: subname, type: type),
            retryPolicy: .idempotentWrite()
        )
    }

    private func paginate<Item: Decodable>(
        pathComponents: [String],
        type: Item.Type
    ) async throws -> [Item] {
        let firstURL = try endpointURL(
            pathComponents: pathComponents,
            queryItems: [URLQueryItem(name: "cursor", value: "")]
        )
        return try await client.paginate(from: firstURL) { url in
            let response = try await authenticatedRequest(method: "GET", url: url, retryPolicy: .transientRead())
            return try (
                client.decode([Item].self, from: response),
                nextLink(from: response.response.value(forHTTPHeaderField: "Link"))
            )
        }
    }

    private func nextLink(from header: String?) throws -> URL? {
        guard let header else { return nil }
        for entry in header.split(separator: ",") {
            let value = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.contains("rel=\"next\"") || value.contains("rel=next") else { continue }
            guard let start = value.firstIndex(of: "<"), let end = value[start...].firstIndex(of: ">"),
                  let url = URL(string: String(value[value.index(after: start) ..< end])), client.isTrusted(url)
            else {
                throw ProviderAPIError.invalidURL(provider: .deSEC)
            }
            return url
        }
        return nil
    }

    private func rrsetPath(domain: String, subname: String, type: String) -> [String] {
        ["domains", domain, "rrsets", subname.isEmpty ? "@" : subname, type.uppercased()]
    }

    private func authenticatedRequest(
        method: String,
        pathComponents: [String],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        try await authenticatedRequest(
            method: method,
            url: endpointURL(pathComponents: pathComponents),
            body: body,
            retryPolicy: retryPolicy
        )
    }

    private func authenticatedRequest(
        method: String,
        url: URL,
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        guard let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .deSEC, field: "API Token")
        }
        return try await client.send(
            method: method,
            url: url,
            headers: ["Authorization": "Token \(token)"],
            body: body,
            retryPolicy: retryPolicy
        )
    }

    private func endpointURL(
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        let url = try client.url(pathComponents: pathComponents, queryItems: queryItems)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ProviderAPIError.invalidURL(provider: .deSEC)
        }
        if !components.path.hasSuffix("/") { components.path.append("/") }
        guard let resolved = components.url else { throw ProviderAPIError.invalidURL(provider: .deSEC) }
        return resolved
    }
}
