import AvgeekNetworking
import Foundation

final class IONOSService {
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        apiKeyProvider: @escaping () -> String?,
        baseURL: URL = URL(string: Configuration.API.ionosBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep
    ) {
        client = ProviderHTTPClient(
            provider: .ionos,
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: {
                guard let apiKey = apiKeyProvider()?.trimmed, !apiKey.isEmpty else {
                    throw ProviderAPIError.missingCredential(provider: .ionos, field: "API key")
                }
                return ["X-API-Key": apiKey]
            },
            sleep: sleep
        )
    }

    func listZones() async throws -> [IONOSZone] {
        let response = try await client.send(
            method: "GET",
            pathComponents: ["v1", "zones"],
            retryPolicy: .transientRead()
        )
        return try client.decode([IONOSZone].self, from: response)
    }

    func getZone(id: String) async throws -> IONOSCustomerZone {
        let response = try await client.send(
            method: "GET",
            pathComponents: ["v1", "zones", id],
            retryPolicy: .transientRead()
        )
        return try client.decode(IONOSCustomerZone.self, from: response)
    }

    func getRecord(zoneId: String, recordId: String) async throws -> IONOSRecord {
        let response = try await client.send(
            method: "GET",
            pathComponents: ["v1", "zones", zoneId, "records", recordId],
            retryPolicy: .transientRead()
        )
        return try client.decode(IONOSRecord.self, from: response)
    }

    func createRecords(zoneId: String, requests: [IONOSRecordCreateRequest]) async throws -> [IONOSRecord] {
        let response = try await client.send(
            method: "POST",
            pathComponents: ["v1", "zones", zoneId, "records"],
            body: encoder.encode(requests)
        )
        return try client.decode([IONOSRecord].self, from: response)
    }

    func updateRecord(
        zoneId: String,
        recordId: String,
        request body: IONOSRecordUpdateRequest
    ) async throws -> IONOSRecord {
        let response = try await client.send(
            method: "PUT",
            pathComponents: ["v1", "zones", zoneId, "records", recordId],
            body: encoder.encode(body)
        )
        return try client.decode(IONOSRecord.self, from: response)
    }

    func deleteRecord(zoneId: String, recordId: String) async throws {
        _ = try await client.send(
            method: "DELETE",
            pathComponents: ["v1", "zones", zoneId, "records", recordId]
        )
    }
}
