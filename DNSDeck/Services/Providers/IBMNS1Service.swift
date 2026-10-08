import AvgeekNetworking
import Foundation

final class IBMNS1Service {
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        apiKeyProvider: @escaping () -> String?,
        baseURL: URL = URL(string: Configuration.API.ibmNS1Base)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        client = ProviderHTTPClient(
            provider: .ibmNS1,
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: {
                guard let apiKey = apiKeyProvider()?.trimmed, !apiKey.isEmpty else {
                    throw ProviderAPIError.missingCredential(provider: .ibmNS1, field: "API Key Secret")
                }
                return ["X-NSONE-Key": apiKey]
            },
            sleep: sleep
        )
    }

    func listZones() async throws -> [IBMNS1Zone] {
        try await paginate(url: client.url(pathComponents: ["zones"])) { response in
            try self.client.decode([IBMNS1Zone].self, from: response)
        }
    }

    func getZone(name: String) async throws -> IBMNS1Zone {
        let zones: [IBMNS1Zone] = try await paginate(
            url: client.url(pathComponents: ["zones", name])
        ) { response in
            try [self.client.decode(IBMNS1Zone.self, from: response)]
        }
        guard let zone = zones.first else { throw ProviderAPIError.invalidResponse(provider: .ibmNS1) }
        guard zones.count > 1 else { return zone }
        return IBMNS1Zone(
            id: zone.id,
            zone: zone.zone,
            dnsServers: zone.dnsServers,
            ttl: zone.ttl,
            nxTTL: zone.nxTTL,
            serial: zone.serial,
            link: zone.link,
            networks: zone.networks,
            records: zones.flatMap { $0.records ?? [] },
            secondary: zone.secondary,
            dnssec: zone.dnssec,
            tags: zone.tags
        )
    }

    func createZone(name: String) async throws -> IBMNS1Zone {
        let response = try await client.send(
            method: "PUT",
            url: client.url(pathComponents: ["zones", name]),
            body: encoder.encode(IBMNS1CreateZoneRequest(zone: name))
        )
        return try client.decode(IBMNS1Zone.self, from: response)
    }

    func deleteZone(name: String) async throws {
        _ = try await client.send(method: "DELETE", url: client.url(pathComponents: ["zones", name]))
    }

    func listRecords(zoneName: String) async throws -> [IBMNS1Record] {
        let zone = try await getZone(name: zoneName)
        var records: [IBMNS1Record] = []
        for summary in zone.records ?? [] {
            try await records.append(getRecord(zone: zoneName, domain: summary.domain, type: summary.type))
        }
        return records
    }

    func getRecord(zone: String, domain: String, type: String) async throws -> IBMNS1Record {
        let response = try await client.send(
            method: "GET",
            url: client.url(pathComponents: ["zones", zone, domain, type]),
            retryPolicy: .transientRead()
        )
        return try client.decode(IBMNS1Record.self, from: response)
    }

    func createRecord(_ record: IBMNS1Record) async throws {
        _ = try await client.send(
            method: "PUT",
            url: client.url(pathComponents: ["zones", record.zone, record.domain, record.type]),
            body: encoder.encode(record.mutation())
        )
    }

    func updateRecord(_ record: IBMNS1Record) async throws {
        _ = try await client.send(
            method: "POST",
            url: client.url(pathComponents: ["zones", record.zone, record.domain, record.type]),
            body: encoder.encode(record.mutation())
        )
    }

    func deleteRecord(zone: String, domain: String, type: String) async throws {
        _ = try await client.send(
            method: "DELETE",
            url: client.url(pathComponents: ["zones", zone, domain, type])
        )
    }

    private func paginate<Item>(
        url: URL,
        decode: (ProviderHTTPResponse) throws -> [Item]
    ) async throws -> [Item] {
        try await client.paginate(from: url) { pageURL in
            let response = try await client.send(method: "GET", url: pageURL, retryPolicy: .transientRead())
            return try (
                decode(response),
                nextLink(response.response.value(forHTTPHeaderField: "Link"))
            )
        }
    }

    private func nextLink(_ header: String?) throws -> URL? {
        guard let header else { return nil }
        for entry in header.split(separator: ",") {
            let value = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.contains("rel=\"next\"") || value.contains("rel=next") else { continue }
            guard let start = value.firstIndex(of: "<"), let end = value[start...].firstIndex(of: ">"),
                  let url = URL(string: String(value[value.index(after: start) ..< end]))
            else {
                throw ProviderAPIError.invalidURL(provider: .ibmNS1)
            }
            guard client.isTrusted(url) else { throw ProviderAPIError.untrustedURL(provider: .ibmNS1, url: url) }
            return url
        }
        return nil
    }
}
