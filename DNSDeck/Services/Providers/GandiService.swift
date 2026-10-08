import AvgeekNetworking
import Foundation

final class GandiService {
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        tokenProvider: @escaping () -> String?,
        baseURL: URL = URL(string: Configuration.API.gandiBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        client = ProviderHTTPClient(
            provider: .gandi,
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: {
                guard let token = tokenProvider()?.trimmed, !token.isEmpty else {
                    throw ProviderAPIError.missingCredential(provider: .gandi, field: "Personal Access Token")
                }
                return ["Authorization": "Bearer \(token)"]
            },
            sleep: sleep
        )
    }

    func listDomains() async throws -> [GandiDomain] {
        try await paginate(pathComponents: ["livedns", "domains"], type: GandiDomain.self)
    }

    func getDomain(name: String) async throws -> GandiDomain {
        let response = try await client.send(
            method: "GET",
            pathComponents: ["livedns", "domains", name],
            retryPolicy: .transientRead()
        )
        return try client.decode(GandiDomain.self, from: response)
    }

    func createDomain(name: String) async throws -> GandiDomain {
        _ = try await client.send(
            method: "POST",
            pathComponents: ["livedns", "domains"],
            body: encoder.encode(GandiCreateDomainRequest(fqdn: name))
        )
        return try await getDomain(name: name)
    }

    func nameservers(domain: String) async throws -> [String] {
        let response = try await client.send(
            method: "GET",
            pathComponents: ["livedns", "domains", domain, "nameservers"],
            retryPolicy: .transientRead()
        )
        return try client.decode([String].self, from: response)
    }

    func listRecordSets(domain: String) async throws -> [GandiRecordSet] {
        try await paginate(
            pathComponents: ["livedns", "domains", domain, "records"],
            type: GandiRecordSet.self
        )
    }

    func createRecordSet(
        domain: String,
        name: String,
        type: String,
        request: GandiRecordSetWriteRequest
    ) async throws {
        _ = try await client.send(
            method: "POST",
            pathComponents: ["livedns", "domains", domain, "records", name, type],
            body: encoder.encode(request)
        )
    }

    func replaceRecordSet(
        domain: String,
        name: String,
        type: String,
        request: GandiRecordSetWriteRequest
    ) async throws {
        _ = try await client.send(
            method: "PUT",
            pathComponents: ["livedns", "domains", domain, "records", name, type],
            body: encoder.encode(request)
        )
    }

    func deleteRecordSet(domain: String, name: String, type: String) async throws {
        _ = try await client.send(
            method: "DELETE",
            pathComponents: ["livedns", "domains", domain, "records", name, type]
        )
    }

    private func paginate<Item: Decodable>(
        pathComponents: [String],
        type: Item.Type
    ) async throws -> [Item] {
        var itemCount = 0
        return try await client.paginate(from: 1) { page in
            let response = try await client.send(
                method: "GET",
                pathComponents: pathComponents,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "per_page", value: "100"),
                ],
                retryPolicy: .transientRead()
            )
            let pageItems = try client.decode([Item].self, from: response)
            itemCount += pageItems.count
            let total = response.response.value(forHTTPHeaderField: "Total-Count").flatMap(Int.init)
            let next = if let total {
                itemCount < total && !pageItems.isEmpty ? page + 1 : nil
            } else {
                pageItems.count == 100 ? page + 1 : nil
            }
            return (pageItems, next)
        }
    }
}
