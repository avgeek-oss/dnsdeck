import AvgeekNetworking
import Foundation

final class UltraDNSService {
    typealias Credentials = (username: String?, password: String?)

    private let credentialsProvider: () -> Credentials
    private let client: ProviderHTTPClient
    private let baseURL: URL
    private let now: () -> Date
    private let tokenLock = NSLock()
    private var cachedToken: String?
    private var tokenExpiry: Date?

    private var cachedTokenState: (token: String?, expiry: Date?) {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return (cachedToken, tokenExpiry)
    }

    init(
        credentialsProvider: @escaping () -> Credentials,
        baseURL: URL = URL(string: Configuration.API.ultraDNSBase)!,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep,
        now: @escaping () -> Date = Date.init
    ) {
        self.credentialsProvider = credentialsProvider
        self.baseURL = baseURL
        self.now = now
        client = ProviderHTTPClient(provider: .ultraDNS, baseURL: baseURL, transport: transport, sleep: sleep, now: now)
    }

    func listZones() async throws -> [UltraDNSZone] {
        var zones: [UltraDNSZone] = []
        var cursor: String?
        var seen: Set<String> = []
        repeat {
            if let cursor, !seen.insert(cursor).inserted {
                throw ProviderAPIError.operationFailed(
                    provider: .ultraDNS,
                    operation: "zone listing",
                    message: "cursor cycle detected"
                )
            }
            let response = try await send(
                method: "GET",
                url: url(
                    segments: ["v3", "zones"],
                    queryItems: [URLQueryItem(name: "limit", value: "1000")] +
                        (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
                ),
                retryPolicy: .transientRead()
            )
            let page = try client.decode(UltraDNSZoneListResponse.self, from: response)
            zones.append(contentsOf: page.zones)
            cursor = page.cursorInfo?.next
            if seen.count >= 1000 {
                throw ProviderAPIError.operationFailed(
                    provider: .ultraDNS,
                    operation: "zone listing",
                    message: "pagination exceeded 1000 pages"
                )
            }
        } while cursor != nil
        return zones
    }

    func getZone(name: String) async throws -> UltraDNSZone {
        let response = try await send(method: "GET", url: url(segments: ["zones", name]), retryPolicy: .transientRead())
        return try client.decode(UltraDNSZone.self, from: response)
    }

    func deleteZone(name: String) async throws {
        _ = try await send(method: "DELETE", url: url(segments: ["zones", name]), retryPolicy: .never)
    }

    func listRRSets(zoneName: String) async throws -> [UltraDNSRRSet] {
        var offset = 0
        var records: [UltraDNSRRSet] = []
        for _ in 0 ..< 1000 {
            let response = try await send(
                method: "GET",
                url: url(
                    segments: ["zones", zoneName, "rrsets"],
                    queryItems: [
                        URLQueryItem(name: "offset", value: String(offset)),
                        URLQueryItem(name: "limit", value: "1000"),
                        URLQueryItem(name: "systemGeneratedStatus", value: "true"),
                    ]
                ),
                retryPolicy: .transientRead()
            )
            let page = try client.decode(UltraDNSRRSetListResponse.self, from: response)
            records.append(contentsOf: page.rrSets)
            guard let result = page.resultInfo,
                  result.returnedCount > 0,
                  result.offset + result.returnedCount < result.totalCount
            else { return records }
            offset = result.offset + result.returnedCount
        }
        throw ProviderAPIError.operationFailed(
            provider: .ultraDNS,
            operation: "RRset listing",
            message: "pagination exceeded 1000 pages"
        )
    }

    func createRRSet(zone: String, owner: String, type: String, write: UltraDNSRRSetWrite) async throws {
        _ = try await mutate(method: "POST", zone: zone, owner: owner, type: type, write: write)
    }

    func replaceRRSet(zone: String, owner: String, type: String, write: UltraDNSRRSetWrite) async throws {
        _ = try await mutate(method: "PUT", zone: zone, owner: owner, type: type, write: write)
    }

    func deleteRRSet(zone: String, owner: String, type: String) async throws {
        _ = try await send(
            method: "DELETE",
            url: url(segments: ["zones", zone, "rrsets", type, owner]),
            retryPolicy: .never
        )
    }

    private func mutate(
        method: String,
        zone: String,
        owner: String,
        type: String,
        write: UltraDNSRRSetWrite
    ) async throws -> ProviderHTTPResponse {
        try await send(
            method: method,
            url: url(segments: ["zones", zone, "rrsets", type, owner]),
            body: JSONEncoder().encode(write),
            retryPolicy: .never
        )
    }

    private func send(
        method: String,
        url: URL,
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy
    ) async throws -> ProviderHTTPResponse {
        try await client.send(
            method: method,
            url: url,
            headers: ["Authorization": "Bearer \(accessToken())"],
            body: body,
            retryPolicy: retryPolicy
        )
    }

    private func accessToken() async throws -> String {
        let (token, expiry) = cachedTokenState
        if let token, let expiry, expiry > now() { return token }

        let credentials = credentialsProvider()
        let username = try required(credentials.username, field: "Username")
        let password = try required(credentials.password, field: "Password")
        let form = [
            "grant_type=password",
            "username=\(ultraDNSFormEncode(username))",
            "password=\(ultraDNSFormEncode(password))",
        ].joined(separator: "&")
        let response = try await client.send(
            method: "POST",
            url: url(segments: ["authorization", "token"]),
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(form.utf8),
            retryPolicy: .never
        )
        let tokenResponse = try client.decode(UltraDNSAccessTokenResponse.self, from: response)
        cacheToken(
            tokenResponse.accessToken,
            expiry: now().addingTimeInterval(TimeInterval(max(0, tokenResponse.expiresIn.intValue - 60)))
        )
        return tokenResponse.accessToken
    }

    private func cacheToken(_ token: String, expiry: Date) {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        cachedToken = token
        tokenExpiry = expiry
    }

    private func required(_ value: String?, field: String) throws -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .ultraDNS, field: field)
        }
        return value
    }

    private func url(segments: [String], queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ProviderAPIError.invalidURL(provider: .ultraDNS)
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encoded = try segments.map { segment -> String in
            guard let value = segment.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw ProviderAPIError.invalidURL(provider: .ultraDNS)
            }
            return value
        }
        components
            .percentEncodedPath =
            ([components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))] + encoded)
                .filter { !$0.isEmpty }
                .joined(separator: "/")
        components.percentEncodedPath = "/\(components.percentEncodedPath)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url, client.isTrusted(url) else {
            throw ProviderAPIError.invalidURL(provider: .ultraDNS)
        }
        return url
    }
}

private func ultraDNSFormEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
