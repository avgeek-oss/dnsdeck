import AvgeekNetworking
import CryptoKit
import Foundation

final class OVHCloudService {
    typealias Credentials = (
        endpoint: String?,
        applicationKey: String?,
        applicationSecret: String?,
        consumerKey: String?
    )

    private struct Connection {
        let client: ProviderHTTPClient
        let applicationKey: String
        let applicationSecret: String
        let consumerKey: String
    }

    static let endpoints = [
        "ovh-eu": URL(string: "https://eu.api.ovh.com/1.0")!,
        "ovh-ca": URL(string: "https://ca.api.ovh.com/1.0")!,
        "ovh-us": URL(string: "https://api.us.ovhcloud.com/1.0")!,
    ]

    private let credentialsProvider: () -> Credentials
    private let transport: any NetworkTransport
    private let sleep: ProviderHTTPClient.Sleep
    private let now: () -> Date
    private let encoder = JSONEncoder()
    private var cachedTimeDelta: TimeInterval?

    init(
        credentialsProvider: @escaping () -> Credentials,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep,
        now: @escaping () -> Date = Date.init
    ) {
        self.credentialsProvider = credentialsProvider
        self.transport = transport
        self.sleep = sleep
        self.now = now
    }

    func listZones() async throws -> [String] {
        let connection = try connection()
        let response = try await request(
            connection: connection,
            method: "GET",
            pathComponents: ["domain", "zone"],
            retryPolicy: .transientRead()
        )
        return try connection.client.decode([String].self, from: response)
    }

    func getZone(name: String) async throws -> OVHCloudZone {
        let connection = try connection()
        let response = try await request(
            connection: connection,
            method: "GET",
            pathComponents: ["domain", "zone", name],
            retryPolicy: .transientRead()
        )
        return try connection.client.decode(OVHCloudZone.self, from: response)
    }

    func listRecords(zoneName: String) async throws -> [OVHCloudRecord] {
        let connection = try connection()
        let response = try await request(
            connection: connection,
            method: "GET",
            pathComponents: ["domain", "zone", zoneName, "record"],
            retryPolicy: .transientRead()
        )
        let ids = try connection.client.decode([Int64].self, from: response)
        var records: [OVHCloudRecord] = []
        for id in ids {
            try await records.append(getRecord(zoneName: zoneName, id: id, connection: connection))
        }
        return records
    }

    func createRecord(zoneName: String, record: OVHCloudRecordCreate) async throws -> OVHCloudRecord {
        let connection = try connection()
        let response = try await request(
            connection: connection,
            method: "POST",
            pathComponents: ["domain", "zone", zoneName, "record"],
            body: encoder.encode(record)
        )
        let created = try connection.client.decode(OVHCloudRecord.self, from: response)
        guard created.id == 0 else { return created }
        return try await resolveCreatedRecord(zoneName: zoneName, expected: record, connection: connection)
    }

    func updateRecord(zoneName: String, id: Int64, record: OVHCloudRecordUpdate) async throws {
        let connection = try connection()
        _ = try await request(
            connection: connection,
            method: "PUT",
            pathComponents: ["domain", "zone", zoneName, "record", String(id)],
            body: encoder.encode(record)
        )
    }

    func deleteRecord(zoneName: String, id: Int64) async throws {
        let connection = try connection()
        _ = try await request(
            connection: connection,
            method: "DELETE",
            pathComponents: ["domain", "zone", zoneName, "record", String(id)]
        )
    }

    func refreshZone(name: String) async throws {
        let connection = try connection()
        _ = try await request(
            connection: connection,
            method: "POST",
            pathComponents: ["domain", "zone", name, "refresh"]
        )
    }

    func updateNameservers(domain: String, nameservers: [String]) async throws {
        let connection = try connection()
        _ = try await request(
            connection: connection,
            method: "POST",
            pathComponents: ["domain", domain, "nameServers", "update"],
            body: encoder.encode(
                OVHCloudNameserverUpdateRequest(
                    nameServer: nameservers.map { OVHCloudNameserver(host: $0) }
                )
            )
        )
    }

    private func resolveCreatedRecord(
        zoneName: String,
        expected: OVHCloudRecordCreate,
        connection: Connection
    ) async throws -> OVHCloudRecord {
        let response = try await request(
            connection: connection,
            method: "GET",
            pathComponents: ["domain", "zone", zoneName, "record"],
            queryItems: [
                URLQueryItem(name: "fieldType", value: expected.fieldType),
                URLQueryItem(name: "subDomain", value: expected.subDomain ?? ""),
            ],
            retryPolicy: .transientRead()
        )
        let ids = try connection.client.decode([Int64].self, from: response).sorted(by: >)
        for id in ids {
            let candidate = try await getRecord(zoneName: zoneName, id: id, connection: connection)
            if candidate.fieldType == expected.fieldType,
               (candidate.subDomain ?? "") == (expected.subDomain ?? ""),
               candidate.target == expected.target
            {
                return candidate
            }
        }
        throw ProviderAPIError.operationFailed(
            provider: .ovhCloud,
            operation: "record creation",
            message: "The API returned id 0 and the created record could not be resolved."
        )
    }

    private func getRecord(
        zoneName: String,
        id: Int64,
        connection: Connection
    ) async throws -> OVHCloudRecord {
        let response = try await request(
            connection: connection,
            method: "GET",
            pathComponents: ["domain", "zone", zoneName, "record", String(id)],
            retryPolicy: .transientRead()
        )
        return try connection.client.decode(OVHCloudRecord.self, from: response)
    }

    private func connection() throws -> Connection {
        let credentials = credentialsProvider()
        guard let endpointName = credentials.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let endpoint = Self.endpoints[endpointName]
        else {
            throw ProviderAPIError.missingCredential(provider: .ovhCloud, field: "API Region")
        }
        guard let applicationKey = credentials.applicationKey?.trimmedNonEmpty else {
            throw ProviderAPIError.missingCredential(provider: .ovhCloud, field: "Application Key")
        }
        guard let applicationSecret = credentials.applicationSecret?.trimmedNonEmpty else {
            throw ProviderAPIError.missingCredential(provider: .ovhCloud, field: "Application Secret")
        }
        guard let consumerKey = credentials.consumerKey?.trimmedNonEmpty else {
            throw ProviderAPIError.missingCredential(provider: .ovhCloud, field: "Consumer Key")
        }
        return Connection(
            client: ProviderHTTPClient(
                provider: .ovhCloud,
                baseURL: endpoint,
                transport: transport,
                sleep: sleep,
                now: now
            ),
            applicationKey: applicationKey,
            applicationSecret: applicationSecret,
            consumerKey: consumerKey
        )
    }

    private func request(
        connection: Connection,
        method: String,
        pathComponents: [String],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy = .never
    ) async throws -> ProviderHTTPResponse {
        let url = try connection.client.url(pathComponents: pathComponents, queryItems: queryItems)
        let timestamp = try await serverTimestamp(connection: connection)
        let bodyString = body.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let signatureInput = [
            connection.applicationSecret,
            connection.consumerKey,
            method,
            url.absoluteString,
            bodyString,
            String(timestamp),
        ].joined(separator: "+")
        let digest = Insecure.SHA1.hash(data: Data(signatureInput.utf8)).map { String(format: "%02x", $0) }.joined()
        return try await connection.client.send(
            method: method,
            url: url,
            headers: [
                "X-Ovh-Application": connection.applicationKey,
                "X-Ovh-Consumer": connection.consumerKey,
                "X-Ovh-Signature": "$1$\(digest)",
                "X-Ovh-Timestamp": String(timestamp),
            ],
            body: body,
            retryPolicy: retryPolicy
        )
    }

    private func serverTimestamp(connection: Connection) async throws -> Int64 {
        if let cachedTimeDelta {
            return Int64(now().timeIntervalSince1970 - cachedTimeDelta)
        }
        let response = try await connection.client.send(
            method: "GET",
            url: connection.client.url(pathComponents: ["auth", "time"]),
            retryPolicy: .transientRead()
        )
        let serverTime = try connection.client.decode(Int64.self, from: response)
        cachedTimeDelta = now().timeIntervalSince1970 - TimeInterval(serverTime)
        return serverTime
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
