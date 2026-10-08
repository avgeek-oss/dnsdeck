import AvgeekNetworking
import Foundation

final class DigitalOceanService {
    static let nameservers = [
        "ns1.digitalocean.com",
        "ns2.digitalocean.com",
        "ns3.digitalocean.com",
    ]

    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        tokenProvider: @escaping () -> String?,
        baseURL: URL = URL(string: Configuration.API.digitalOceanBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        client = ProviderHTTPClient(
            provider: .digitalOcean,
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: {
                guard let token = tokenProvider()?.trimmed, !token.isEmpty else {
                    throw ProviderAPIError.missingCredential(provider: .digitalOcean, field: "API token")
                }
                return ["Authorization": "Bearer \(token)"]
            },
            sleep: sleep
        )
    }

    func listDomains() async throws -> [DigitalOceanDomain] {
        let firstURL = try client.url(
            pathComponents: ["domains"],
            queryItems: [URLQueryItem(name: "per_page", value: "200")]
        )
        return try await paginate(firstURL: firstURL, envelope: DigitalOceanDomainsEnvelope.self) {
            ($0.domains, $0.links?.pages?.next)
        }
    }

    func getDomain(name: String) async throws -> DigitalOceanDomain {
        let response = try await client.send(
            method: "GET",
            pathComponents: ["domains", name],
            retryPolicy: .transientRead()
        )
        return try client.decode(DigitalOceanDomainEnvelope.self, from: response).domain
    }

    func createDomain(name: String) async throws -> DigitalOceanDomain {
        let response = try await client.send(
            method: "POST",
            pathComponents: ["domains"],
            body: encoder.encode(DigitalOceanCreateDomainRequest(name: name))
        )
        return try client.decode(DigitalOceanDomainEnvelope.self, from: response).domain
    }

    func deleteDomain(name: String) async throws {
        _ = try await client.send(method: "DELETE", pathComponents: ["domains", name])
    }

    func listRecords(domain: String) async throws -> [DigitalOceanDomainRecord] {
        let firstURL = try client.url(
            pathComponents: ["domains", domain, "records"],
            queryItems: [URLQueryItem(name: "per_page", value: "200")]
        )
        return try await paginate(firstURL: firstURL, envelope: DigitalOceanDomainRecordsEnvelope.self) {
            ($0.domainRecords, $0.links?.pages?.next)
        }
    }

    func createRecord(
        domain: String,
        request: DigitalOceanRecordWriteRequest
    ) async throws -> DigitalOceanDomainRecord {
        let response = try await client.send(
            method: "POST",
            pathComponents: ["domains", domain, "records"],
            body: encoder.encode(request)
        )
        return try client.decode(DigitalOceanDomainRecordEnvelope.self, from: response).domainRecord
    }

    func updateRecord(
        domain: String,
        recordId: Int,
        request: DigitalOceanRecordWriteRequest
    ) async throws -> DigitalOceanDomainRecord {
        let response = try await client.send(
            method: "PUT",
            pathComponents: ["domains", domain, "records", String(recordId)],
            body: encoder.encode(request)
        )
        return try client.decode(DigitalOceanDomainRecordEnvelope.self, from: response).domainRecord
    }

    func deleteRecord(domain: String, recordId: Int) async throws {
        _ = try await client.send(
            method: "DELETE",
            pathComponents: ["domains", domain, "records", String(recordId)]
        )
    }

    private func paginate<Envelope: Decodable, Element>(
        firstURL: URL,
        envelope: Envelope.Type,
        values: (Envelope) -> ([Element], URL?)
    ) async throws -> [Element] {
        try await client.paginate(from: firstURL) { url in
            let response = try await client.send(
                method: "GET",
                url: url,
                retryPolicy: .transientRead()
            )
            let result = try values(client.decode(envelope, from: response))
            if let candidate = result.1, !client.isTrusted(candidate) {
                throw ProviderAPIError.untrustedURL(provider: .digitalOcean, url: candidate)
            }
            return result
        }
    }
}
