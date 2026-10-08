import AvgeekNetworking
import Foundation

final class VultrService {
    static let nameservers = ["ns1.vultr.com", "ns2.vultr.com"]

    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        tokenProvider: @escaping () -> String?,
        baseURL: URL = URL(string: Configuration.API.vultrBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        client = ProviderHTTPClient(
            provider: .vultr,
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: {
                guard let token = tokenProvider()?.trimmed, !token.isEmpty else {
                    throw ProviderAPIError.missingCredential(provider: .vultr, field: "API key")
                }
                return ["Authorization": "Bearer \(token)"]
            },
            sleep: sleep
        )
    }

    func listDomains() async throws -> [VultrDomain] {
        try await paginate(pathComponents: ["domains"], keyPath: \VultrDomainsEnvelope.domains)
    }

    func getDomain(name: String) async throws -> VultrDomain {
        let response = try await client.send(
            method: "GET",
            pathComponents: ["domains", name],
            retryPolicy: .transientRead()
        )
        return try client.decode(VultrDomainEnvelope.self, from: response).domain
    }

    func createDomain(name: String) async throws -> VultrDomain {
        let response = try await client.send(
            method: "POST",
            pathComponents: ["domains"],
            body: encoder.encode(VultrCreateDomainRequest(domain: name))
        )
        return try client.decode(VultrDomainEnvelope.self, from: response).domain
    }

    func deleteDomain(name: String) async throws {
        _ = try await client.send(method: "DELETE", pathComponents: ["domains", name])
    }

    func listRecords(domain: String) async throws -> [VultrDomainRecord] {
        try await paginate(
            pathComponents: ["domains", domain, "records"],
            keyPath: \VultrRecordsEnvelope.records
        )
    }

    func createRecord(domain: String, request: VultrRecordCreateRequest) async throws -> VultrDomainRecord {
        let response = try await client.send(
            method: "POST",
            pathComponents: ["domains", domain, "records"],
            body: encoder.encode(request)
        )
        return try client.decode(VultrRecordEnvelope.self, from: response).record
    }

    func updateRecord(domain: String, recordId: String, request: VultrRecordUpdateRequest) async throws {
        _ = try await client.send(
            method: "PATCH",
            pathComponents: ["domains", domain, "records", recordId],
            body: encoder.encode(request)
        )
    }

    func deleteRecord(domain: String, recordId: String) async throws {
        _ = try await client.send(
            method: "DELETE",
            pathComponents: ["domains", domain, "records", recordId]
        )
    }

    private func paginate<Item: Decodable, Envelope: Decodable & VultrPaginatedEnvelope>(
        pathComponents: [String],
        keyPath: KeyPath<Envelope, [Item]>
    ) async throws -> [Item] {
        try await client.paginate(from: "") { cursor in
            var query = [URLQueryItem(name: "per_page", value: "500")]
            if !cursor.isEmpty { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let response = try await client.send(
                method: "GET",
                pathComponents: pathComponents,
                queryItems: query,
                retryPolicy: .transientRead()
            )
            let envelope = try client.decode(Envelope.self, from: response)
            let next = envelope.vultrMeta?.links?.next.flatMap { $0.isEmpty ? nil : $0 }
            return (envelope[keyPath: keyPath], next)
        }
    }
}

private protocol VultrPaginatedEnvelope: Decodable {
    var vultrMeta: VultrMeta? { get }
}

extension VultrDomainsEnvelope: VultrPaginatedEnvelope {
    var vultrMeta: VultrMeta? {
        meta
    }
}

extension VultrRecordsEnvelope: VultrPaginatedEnvelope {
    var vultrMeta: VultrMeta? {
        meta
    }
}
