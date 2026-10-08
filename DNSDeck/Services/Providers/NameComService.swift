import AvgeekNetworking
import Foundation

final class NameComService {
    typealias Credentials = (username: String?, token: String?)

    private let credentialsProvider: () -> Credentials
    private let client: ProviderHTTPClient
    private let encoder = JSONEncoder()

    init(
        credentialsProvider: @escaping () -> Credentials,
        baseURL: URL = URL(string: Configuration.API.nameComBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep,
        now: @escaping () -> Date = Date.init
    ) {
        self.credentialsProvider = credentialsProvider
        client = ProviderHTTPClient(
            provider: .nameCom,
            baseURL: baseURL,
            transport: transport,
            sleep: sleep,
            now: now
        )
    }

    func listDomains() async throws -> [NameComDomain] {
        try await paginate(pathComponents: ["core", "v1", "domains"], response: NameComDomainListResponse.self) {
            ($0.domains, $0.nextPage)
        }
    }

    func getDomain(name: String) async throws -> NameComDomain {
        let response = try await request(
            method: "GET",
            pathComponents: ["core", "v1", "domains", name],
            retryPolicy: .transientRead()
        )
        return try client.decode(NameComDomain.self, from: response)
    }

    func updateNameservers(domain: String, nameservers: [String]) async throws {
        _ = try await request(
            method: "POST",
            pathComponents: ["core", "v1", "domains", "\(domain):setNameservers"],
            body: encoder.encode(NameComNameserverUpdateRequest(nameservers: nameservers))
        )
    }

    func listRecords(domain: String) async throws -> [NameComDNSRecord] {
        try await paginate(
            pathComponents: ["core", "v1", "domains", domain, "records"],
            response: NameComRecordListResponse.self
        ) {
            ($0.records, $0.nextPage)
        }
    }

    func createRecord(domain: String, request body: NameComRecordWriteRequest) async throws -> NameComDNSRecord {
        let response = try await request(
            method: "POST",
            pathComponents: ["core", "v1", "domains", domain, "records"],
            body: encoder.encode(body)
        )
        return try client.decode(NameComDNSRecord.self, from: response)
    }

    func updateRecord(
        domain: String,
        recordId: Int,
        request body: NameComRecordWriteRequest
    ) async throws -> NameComDNSRecord {
        let response = try await request(
            method: "PUT",
            pathComponents: ["core", "v1", "domains", domain, "records", String(recordId)],
            body: encoder.encode(body)
        )
        return try client.decode(NameComDNSRecord.self, from: response)
    }

    func deleteRecord(domain: String, recordId: Int) async throws {
        _ = try await request(
            method: "DELETE",
            pathComponents: ["core", "v1", "domains", domain, "records", String(recordId)]
        )
    }

    private func paginate<Response: Decodable, Value>(
        pathComponents: [String],
        response: Response.Type,
        values: (Response) -> ([Value], Int?)
    ) async throws -> [Value] {
        try await client.paginate(from: 1) { page in
            let result = try await request(
                method: "GET",
                pathComponents: pathComponents,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "perPage", value: "1000"),
                ],
                retryPolicy: .transientRead()
            )
            let pageValues = try values(client.decode(response, from: result))
            return (pageValues.0, pageValues.1.flatMap { $0 > 0 ? $0 : nil })
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
        let encoded = Data("\(credentials.username):\(credentials.token)".utf8).base64EncodedString()
        return try await client.send(
            method: method,
            url: client.url(pathComponents: pathComponents, queryItems: queryItems),
            headers: ["Authorization": "Basic \(encoded)"],
            body: body,
            retryPolicy: retryPolicy
        )
    }

    private func credentials() throws -> (username: String, token: String) {
        let credentials = credentialsProvider()
        guard let username = credentials.username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty
        else {
            throw ProviderAPIError.missingCredential(provider: .nameCom, field: "username")
        }
        guard let token = credentials.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .nameCom, field: "API token")
        }
        return (username, token)
    }
}
