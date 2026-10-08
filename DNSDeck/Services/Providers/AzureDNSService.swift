import AvgeekNetworking
import Foundation

final class AzureDNSService {
    typealias Credentials = (
        tenantId: String?,
        clientId: String?,
        clientSecret: String?,
        subscriptionId: String?,
        resourceGroup: String?
    )

    private static let apiVersion = "2018-05-01"
    private static let maximumPages = 1000
    private static let maximumDeletePolls = 60

    private let credentialsProvider: () -> Credentials
    private let accessTokenProvider: (() async throws -> String)?
    private let managementClient: ProviderHTTPClient
    private let identityClient: ProviderHTTPClient
    private let managementScope: String
    private let sleep: ProviderHTTPClient.Sleep
    private let now: () -> Date

    private let tokenLock = NSLock()
    private var cachedAccessToken: String?
    private var tokenExpiry: Date?

    private var cachedTokenState: (token: String?, expiry: Date?) {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return (cachedAccessToken, tokenExpiry)
    }

    init(
        credentialsProvider: @escaping () -> Credentials,
        resourceManagerBaseURL: URL = URL(string: Configuration.API.azureResourceManagerBase)!,
        identityBaseURL: URL = URL(string: Configuration.API.azureIdentityBase)!,
        managementScope: String = "https://management.azure.com/.default",
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping ProviderHTTPClient.Sleep = ProviderHTTPClient.liveSleep,
        now: @escaping () -> Date = Date.init,
        accessTokenProvider: (() async throws -> String)? = nil
    ) {
        self.credentialsProvider = credentialsProvider
        self.accessTokenProvider = accessTokenProvider
        self.managementScope = managementScope
        self.sleep = sleep
        self.now = now
        managementClient = ProviderHTTPClient(
            provider: .azureDNS,
            baseURL: resourceManagerBaseURL,
            transport: transport,
            sleep: sleep,
            now: now
        )
        identityClient = ProviderHTTPClient(
            provider: .azureDNS,
            baseURL: identityBaseURL,
            transport: transport,
            sleep: sleep,
            now: now
        )
    }

    func listZones() async throws -> [AzureDNSZone] {
        let subscriptionId = try subscriptionId()
        var nextURL: URL? = try managementClient.url(
            pathComponents: [
                "subscriptions", subscriptionId, "providers", "Microsoft.Network", "dnszones",
            ],
            queryItems: [URLQueryItem(name: "api-version", value: Self.apiVersion)]
        )
        var seen: Set<String> = []
        var zones: [AzureDNSZone] = []

        for _ in 0 ..< Self.maximumPages {
            guard let url = nextURL else { return zones }
            try recordPaginationURL(url, seen: &seen, operation: "zone listing")
            let response = try await send(method: "GET", url: url, retryPolicy: .transientRead())
            let page = try managementClient.decode(AzureDNSZoneListResponse.self, from: response)
            zones.append(contentsOf: page.value)
            nextURL = try page.nextLink.map(resolvePaginationURL)
        }

        throw ProviderAPIError.operationFailed(
            provider: .azureDNS,
            operation: "zone listing",
            message: "pagination exceeded \(Self.maximumPages) pages"
        )
    }

    func getZone(_ zone: AzureDNSZone) async throws -> AzureDNSZone {
        let url = try zoneURL(zone)
        let response = try await send(method: "GET", url: url, retryPolicy: .transientRead())
        return try managementClient.decode(AzureDNSZone.self, from: response)
    }

    func createZone(name: String) async throws -> AzureDNSZone {
        let resourceGroup = try requiredCredential(credentialsProvider().resourceGroup, field: "Default Resource Group")
        let url = try zoneURL(name: name, resourceGroup: resourceGroup)
        let body = try JSONEncoder().encode(AzureDNSZoneWriteRequest(location: "global"))
        let response = try await send(
            method: "PUT",
            url: url,
            headers: ["If-None-Match": "*"],
            body: body,
            retryPolicy: .transientResponseWrite()
        )
        return try managementClient.decode(AzureDNSZone.self, from: response)
    }

    func deleteZone(_ zone: AzureDNSZone) async throws {
        let response = try await send(
            method: "DELETE",
            url: zoneURL(zone),
            headers: zone.etag.map { ["If-Match": $0] } ?? [:],
            retryPolicy: .transientResponseWrite()
        )
        guard response.response.statusCode == 202 else { return }
        try await pollDeleteOperation(from: response.response)
    }

    func listRecordSets(zone: AzureDNSZone) async throws -> [AzureDNSRecordSet] {
        let resourceGroup = try resourceGroup(for: zone)
        let subscriptionId = try subscriptionId()
        var nextURL: URL? = try managementClient.url(
            pathComponents: [
                "subscriptions", subscriptionId, "resourceGroups", resourceGroup, "providers",
                "Microsoft.Network", "dnsZones", zone.name, "all",
            ],
            queryItems: [URLQueryItem(name: "api-version", value: Self.apiVersion)]
        )
        var seen: Set<String> = []
        var records: [AzureDNSRecordSet] = []

        for _ in 0 ..< Self.maximumPages {
            guard let url = nextURL else { return records }
            try recordPaginationURL(url, seen: &seen, operation: "record-set listing")
            let response = try await send(method: "GET", url: url, retryPolicy: .transientRead())
            let page = try managementClient.decode(AzureDNSRecordSetListResponse.self, from: response)
            records.append(contentsOf: page.value)
            nextURL = try page.nextLink.map(resolvePaginationURL)
        }

        throw ProviderAPIError.operationFailed(
            provider: .azureDNS,
            operation: "record-set listing",
            message: "pagination exceeded \(Self.maximumPages) pages"
        )
    }

    func putRecordSet(
        zone: AzureDNSZone,
        mutation: AzureDNSRecordMutation,
        ifMatch: String? = nil,
        ifNoneMatch: String? = nil
    ) async throws -> AzureDNSRecordSet {
        var headers: [String: String] = [:]
        if let ifMatch { headers["If-Match"] = ifMatch }
        if let ifNoneMatch { headers["If-None-Match"] = ifNoneMatch }
        let body = try JSONEncoder().encode(mutation.request)
        let response = try await send(
            method: "PUT",
            url: recordSetURL(
                zone: zone,
                relativeName: mutation.relativeName,
                type: mutation.type
            ),
            headers: headers,
            body: body,
            retryPolicy: .transientResponseWrite()
        )
        return try managementClient.decode(AzureDNSRecordSet.self, from: response)
    }

    func deleteRecordSet(
        zone: AzureDNSZone,
        relativeName: String,
        type: String,
        etag: String?
    ) async throws {
        _ = try await send(
            method: "DELETE",
            url: recordSetURL(zone: zone, relativeName: relativeName, type: type),
            headers: etag.map { ["If-Match": $0] } ?? [:],
            retryPolicy: .transientResponseWrite()
        )
    }

    private func send(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        retryPolicy: ProviderRetryPolicy
    ) async throws -> ProviderHTTPResponse {
        var authenticatedHeaders = headers
        authenticatedHeaders["Authorization"] = try await "Bearer \(accessToken())"
        return try await managementClient.send(
            method: method,
            url: url,
            headers: authenticatedHeaders,
            body: body,
            retryPolicy: retryPolicy
        )
    }

    private func accessToken() async throws -> String {
        if let accessTokenProvider {
            return try await accessTokenProvider()
        }

        let (token, expiry) = cachedTokenState
        if let token, let expiry, expiry > now() {
            return token
        }

        let credentials = credentialsProvider()
        let tenantId = try requiredCredential(credentials.tenantId, field: "Tenant ID")
        let clientId = try requiredCredential(credentials.clientId, field: "Client ID")
        let clientSecret = try requiredCredential(credentials.clientSecret, field: "Client Secret")
        let tokenURL = try identityClient.url(
            pathComponents: [tenantId, "oauth2", "v2.0", "token"]
        )
        let form = [
            ("client_id", clientId),
            ("client_secret", clientSecret),
            ("grant_type", "client_credentials"),
            ("scope", managementScope),
        ]
        .map { "\(formEncode($0.0))=\(formEncode($0.1))" }
        .joined(separator: "&")
        let response = try await identityClient.send(
            method: "POST",
            url: tokenURL,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(form.utf8),
            retryPolicy: .never
        )
        let tokenResponse = try identityClient.decode(AzureDNSAccessTokenResponse.self, from: response)
        let expiryDate = now().addingTimeInterval(TimeInterval(max(0, tokenResponse.expiresIn - 60)))
        cacheToken(tokenResponse.accessToken, expiry: expiryDate)
        return tokenResponse.accessToken
    }

    private func cacheToken(_ token: String, expiry: Date) {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        cachedAccessToken = token
        tokenExpiry = expiry
    }

    private func subscriptionId() throws -> String {
        try requiredCredential(credentialsProvider().subscriptionId, field: "Subscription ID")
    }

    private func requiredCredential(_ value: String?, field: String) throws -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .azureDNS, field: field)
        }
        return value
    }

    private func resourceGroup(for zone: AzureDNSZone) throws -> String {
        guard let resourceGroup = zone.resourceGroup, !resourceGroup.isEmpty else {
            throw ProviderAPIError.decoding(
                provider: .azureDNS,
                message: "the zone resource ID does not contain a resource group"
            )
        }
        return resourceGroup
    }

    private func zoneURL(_ zone: AzureDNSZone) throws -> URL {
        try zoneURL(name: zone.name, resourceGroup: resourceGroup(for: zone))
    }

    private func zoneURL(name: String, resourceGroup: String) throws -> URL {
        try managementClient.url(
            pathComponents: [
                "subscriptions", subscriptionId(), "resourceGroups", resourceGroup, "providers",
                "Microsoft.Network", "dnsZones", name,
            ],
            queryItems: [URLQueryItem(name: "api-version", value: Self.apiVersion)]
        )
    }

    private func recordSetURL(zone: AzureDNSZone, relativeName: String, type: String) throws -> URL {
        try managementClient.url(
            pathComponents: [
                "subscriptions", subscriptionId(), "resourceGroups", resourceGroup(for: zone), "providers",
                "Microsoft.Network", "dnsZones", zone.name, type.uppercased(), relativeName,
            ],
            queryItems: [URLQueryItem(name: "api-version", value: Self.apiVersion)]
        )
    }

    private func resolvePaginationURL(_ value: String) throws -> URL {
        guard let url = URL(string: value, relativeTo: managementClient.baseURL)?.absoluteURL else {
            throw ProviderAPIError.invalidURL(provider: .azureDNS)
        }
        guard managementClient.isTrusted(url) else {
            throw ProviderAPIError.untrustedURL(provider: .azureDNS, url: url)
        }
        return url
    }

    private func recordPaginationURL(
        _ url: URL,
        seen: inout Set<String>,
        operation: String
    ) throws {
        guard seen.insert(url.absoluteString).inserted else {
            throw ProviderAPIError.operationFailed(
                provider: .azureDNS,
                operation: operation,
                message: "the API returned a pagination cycle"
            )
        }
    }

    private func pollDeleteOperation(from response: HTTPURLResponse) async throws {
        guard let value = response.value(forHTTPHeaderField: "Azure-AsyncOperation") ??
            response.value(forHTTPHeaderField: "Location")
        else {
            throw ProviderAPIError.operationFailed(
                provider: .azureDNS,
                operation: "zone deletion",
                message: "the asynchronous response did not include a status URL"
            )
        }
        let url = try resolvePaginationURL(value)
        var delay = retryDelay(from: response)

        for _ in 0 ..< Self.maximumDeletePolls {
            try await sleep(delay)
            let pollResponse = try await send(method: "GET", url: url, retryPolicy: .transientRead())
            let status = try managementClient.decode(AzureDNSOperationStatus.self, from: pollResponse)
            switch status.status.lowercased() {
            case "succeeded":
                return
            case "failed", "canceled", "cancelled":
                throw ProviderAPIError.operationFailed(
                    provider: .azureDNS,
                    operation: "zone deletion",
                    message: status.error?.message ?? status.error?.code
                )
            case "accepted", "inprogress", "running":
                delay = retryDelay(from: pollResponse.response)
            default:
                throw ProviderAPIError.operationFailed(
                    provider: .azureDNS,
                    operation: "zone deletion",
                    message: "the API returned unknown status \(status.status)"
                )
            }
        }

        throw ProviderAPIError.operationTimedOut(provider: .azureDNS, operation: "zone deletion")
    }

    private func retryDelay(from response: HTTPURLResponse) -> TimeInterval {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value)
        else {
            return 1
        }
        return min(max(0, seconds), 10)
    }

    private func formEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
