import AvgeekNetworking
import Foundation

final class AkamaiCloudService {
    static let nameservers = (1 ... 5).map { "ns\($0).linode.com" }

    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        tokenProvider: @escaping () -> String?,
        baseURL: URL = URL(string: Configuration.API.akamaiCloudBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        client = ProviderHTTPClient(
            provider: .akamaiCloud,
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: {
                guard let token = tokenProvider()?.trimmed, !token.isEmpty else {
                    throw ProviderAPIError.missingCredential(provider: .akamaiCloud, field: "personal access token")
                }
                return ["Authorization": "Bearer \(token)"]
            },
            sleep: sleep
        )
    }

    func listDomains() async throws -> [AkamaiCloudDomain] {
        try await paginate(pathComponents: ["domains"], type: AkamaiCloudDomain.self)
    }

    func getDomain(id: Int) async throws -> AkamaiCloudDomain {
        let response = try await client.send(
            method: "GET",
            pathComponents: ["domains", String(id)],
            retryPolicy: .transientRead()
        )
        return try client.decode(AkamaiCloudDomain.self, from: response)
    }

    func createDomain(name: String) async throws -> AkamaiCloudDomain {
        let request = AkamaiCloudCreateDomainRequest(
            domain: name,
            type: "master",
            status: "active",
            soaEmail: "hostmaster@\(name)",
            ttlSec: 86400
        )
        let response = try await client.send(
            method: "POST",
            pathComponents: ["domains"],
            body: encoder.encode(request)
        )
        return try client.decode(AkamaiCloudDomain.self, from: response)
    }

    func deleteDomain(id: Int) async throws {
        _ = try await client.send(method: "DELETE", pathComponents: ["domains", String(id)])
    }

    func listRecords(domainId: Int) async throws -> [AkamaiCloudDomainRecord] {
        try await paginate(
            pathComponents: ["domains", String(domainId), "records"],
            type: AkamaiCloudDomainRecord.self
        )
    }

    func createRecord(
        domainId: Int,
        request: AkamaiCloudRecordWriteRequest
    ) async throws -> AkamaiCloudDomainRecord {
        let response = try await client.send(
            method: "POST",
            pathComponents: ["domains", String(domainId), "records"],
            body: encoder.encode(request)
        )
        return try client.decode(AkamaiCloudDomainRecord.self, from: response)
    }

    func updateRecord(
        domainId: Int,
        recordId: Int,
        request: AkamaiCloudRecordWriteRequest
    ) async throws -> AkamaiCloudDomainRecord {
        let response = try await client.send(
            method: "PUT",
            pathComponents: ["domains", String(domainId), "records", String(recordId)],
            body: encoder.encode(request)
        )
        return try client.decode(AkamaiCloudDomainRecord.self, from: response)
    }

    func deleteRecord(domainId: Int, recordId: Int) async throws {
        _ = try await client.send(
            method: "DELETE",
            pathComponents: ["domains", String(domainId), "records", String(recordId)]
        )
    }

    private func paginate<Item: Decodable>(
        pathComponents: [String],
        type: Item.Type
    ) async throws -> [Item] {
        try await client.paginate(from: 1) { page in
            let response = try await client.send(
                method: "GET",
                pathComponents: pathComponents,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page_size", value: "500"),
                ],
                retryPolicy: .transientRead()
            )
            let envelope = try client.decode(AkamaiCloudPage<Item>.self, from: response)
            return (envelope.data, envelope.page < envelope.pages ? envelope.page + 1 : nil)
        }
    }
}
