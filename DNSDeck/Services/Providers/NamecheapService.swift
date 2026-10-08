import AvgeekNetworking
import Foundation

final class NamecheapService {
    typealias Credentials = (
        username: String?,
        apiKey: String?,
        clientIp: String?,
        environment: String?
    )
    typealias Sleep = (TimeInterval) async throws -> Void

    private struct Configuration {
        let username: String
        let apiKey: String
        let clientIp: String
        let endpoint: URL
    }

    private let credentialsProvider: () -> Credentials
    private let transport: any NetworkTransport
    private let sleep: Sleep
    private var cachedTLDs: [String]?

    init(
        credentialsProvider: @escaping () -> Credentials,
        transport: any NetworkTransport = NetworkConfiguration.urlSession,
        sleep: @escaping Sleep = ProviderHTTPClient.liveSleep
    ) {
        self.credentialsProvider = credentialsProvider
        self.transport = transport
        self.sleep = sleep
    }

    func listDomains() async throws -> [NamecheapDomain] {
        let tlds = try await tldNames()
        var domains: [NamecheapDomain] = []
        var page = 1
        var totalItems = Int.max

        while domains.count < totalItems {
            guard page <= 1000 else {
                throw ProviderAPIError.invalidResponse(provider: .namecheap)
            }
            let root = try await request(
                command: "namecheap.domains.getList",
                parameters: [
                    "ListType": "ALL",
                    "Page": String(page),
                    "PageSize": "100",
                    "SortBy": "NAME",
                ]
            )
            let pageDomains = try root.descendants(named: "Domain").map { node in
                guard let id = node.attribute("ID"),
                      let name = node.attribute("Name"),
                      let parts = domainParts(name, tlds: tlds)
                else {
                    throw ProviderAPIError.decoding(
                        provider: .namecheap,
                        message: "a domain entry is missing its ID, name, or recognized TLD"
                    )
                }
                return NamecheapDomain(
                    id: id,
                    name: name,
                    sld: parts.sld,
                    tld: parts.tld,
                    isExpired: node.booleanAttribute("IsExpired"),
                    isLocked: node.booleanAttribute("IsLocked"),
                    autoRenew: node.booleanAttribute("AutoRenew"),
                    isOurDNS: node.booleanAttribute("IsOurDNS"),
                    created: node.attribute("Created"),
                    expires: node.attribute("Expires"),
                    nameservers: []
                )
            }
            domains.append(contentsOf: pageDomains)
            totalItems = root.text(named: "TotalItems").flatMap(Int.init) ?? domains.count
            guard !pageDomains.isEmpty || domains.count >= totalItems else {
                throw ProviderAPIError.invalidResponse(provider: .namecheap)
            }
            page += 1
        }
        return domains
    }

    func domainDetails(_ domain: NamecheapDomain) async throws -> NamecheapDomain {
        let root = try await request(
            command: "namecheap.domains.dns.getList",
            parameters: domainParameters(domain)
        )
        guard let result = root.descendant(named: "DomainDNSGetListResult") else {
            throw ProviderAPIError.invalidResponse(provider: .namecheap)
        }
        var detailed = domain
        detailed.nameservers = result.children(named: "Nameserver").compactMap(\.trimmedText)
        return NamecheapDomain(
            id: detailed.id,
            name: detailed.name,
            sld: detailed.sld,
            tld: detailed.tld,
            isExpired: detailed.isExpired,
            isLocked: detailed.isLocked,
            autoRenew: detailed.autoRenew,
            isOurDNS: result.booleanAttribute("IsUsingOurDNS"),
            created: detailed.created,
            expires: detailed.expires,
            nameservers: detailed.nameservers
        )
    }

    func updateNameservers(domain: NamecheapDomain, nameservers: [String]) async throws {
        let root = try await request(
            command: "namecheap.domains.dns.setCustom",
            parameters: domainParameters(domain).merging(
                ["NameServers": nameservers.joined(separator: ",")],
                uniquingKeysWith: { _, explicit in explicit }
            )
        )
        guard root.descendant(named: "DomainDNSSetCustomResult")?.booleanAttribute("Updated") == true else {
            throw ProviderAPIError.operationFailed(
                provider: .namecheap,
                operation: "nameserver update",
                message: "the API did not confirm the delegation change"
            )
        }
    }

    func listHosts(domain: NamecheapDomain) async throws -> [NamecheapHost] {
        guard domain.isOurDNS else {
            throw ProviderAPIError.operationFailed(
                provider: .namecheap,
                operation: "record listing",
                message: "host records are available only while the domain uses Namecheap DNS"
            )
        }
        let root = try await request(
            command: "namecheap.domains.dns.getHosts",
            parameters: domainParameters(domain)
        )
        guard let result = root.descendant(named: "DomainDNSGetHostsResult"),
              result.booleanAttribute("IsUsingOurDNS")
        else {
            throw ProviderAPIError.operationFailed(
                provider: .namecheap,
                operation: "record listing",
                message: "the domain is no longer using Namecheap DNS"
            )
        }
        return try result.children(caseInsensitiveName: "Host").map { node in
            guard let hostId = node.attribute("HostId"),
                  let name = node.attribute("Name"),
                  let type = node.attribute("Type"),
                  let address = node.attribute("Address")
            else {
                throw ProviderAPIError.decoding(
                    provider: .namecheap,
                    message: "a host record is missing its ID, name, type, or address"
                )
            }
            return NamecheapHost(
                hostId: hostId,
                name: name,
                type: type,
                address: address,
                mxPreference: node.attribute("MXPref").flatMap(Int.init),
                ttl: node.attribute("TTL").flatMap(Int.init) ?? DNSProvider.namecheap.defaultTTL
            )
        }
    }

    func createHosts(domain: NamecheapDomain, payload: CreateProviderRecordRequest) async throws {
        let additions = try payload.toNamecheapHosts(zoneName: domain.name)
        try await replaceHosts(domain: domain, operation: "record creation") { $0 + additions }
    }

    func createHosts(
        domain: NamecheapDomain,
        payloads: [CreateProviderRecordRequest]
    ) async -> [Result<Void, Error>] {
        do {
            let additions = try payloads.flatMap {
                try $0.toNamecheapHosts(zoneName: domain.name)
            }
            try await replaceHosts(domain: domain, operation: "batch record creation") {
                $0 + additions
            }
            return payloads.map { _ in .success(()) }
        } catch {
            return payloads.map { _ in .failure(error) }
        }
    }

    func deleteHost(domain: NamecheapDomain, record: NamecheapHost) async throws {
        try await replaceHosts(domain: domain, operation: "record deletion") { current in
            guard current.contains(where: { $0.hostId == record.hostId }) else {
                throw ProviderOperationError.missingRecord(recordId: record.hostId)
            }
            return current.filter { $0.hostId != record.hostId }
        }
    }

    func updateHost(
        domain: NamecheapDomain,
        record: NamecheapHost,
        edits: UpdateProviderRecordRequest
    ) async throws {
        try await replaceHosts(domain: domain, operation: "record update") { current in
            guard let index = current.firstIndex(where: { $0.hostId == record.hostId }) else {
                throw ProviderOperationError.missingRecord(recordId: record.hostId)
            }
            var updated = current
            updated[index] = try edits.toNamecheapHost(zoneName: domain.name, existing: current[index])
            return updated
        }
    }

    private func replaceHosts(
        domain: NamecheapDomain,
        operation: String,
        mutation: ([NamecheapHost]) throws -> [NamecheapHost]
    ) async throws {
        let current = try await listHosts(domain: domain)
        guard let unsafeType = current.first(where: { !$0.isSafelyRoundTrippable })?.type else {
            let expected = try mutation(current)
            try await setHosts(domain: domain, hosts: expected)
            try await verifyHosts(domain: domain, expected: expected, operation: operation)
            return
        }
        throw ProviderAPIError.operationFailed(
            provider: .namecheap,
            operation: operation,
            message: "the zone contains a \(unsafeType) record that the full-replacement API cannot safely preserve"
        )
    }

    private func setHosts(domain: NamecheapDomain, hosts: [NamecheapHost]) async throws {
        var parameters = domainParameters(domain)
        for (offset, host) in hosts.enumerated() {
            let index = offset + 1
            parameters["HostName\(index)"] = host.name
            parameters["RecordType\(index)"] = host.type
            parameters["Address\(index)"] = host.address
            parameters["TTL\(index)"] = String(host.ttl)
            if host.type.uppercased() == "MX" {
                parameters["MXPref\(index)"] = String(host.mxPreference ?? 10)
            }
        }
        let root = try await request(command: "namecheap.domains.dns.setHosts", parameters: parameters)
        guard root.descendant(named: "DomainDNSSetHostsResult")?.booleanAttribute("IsSuccess") == true else {
            throw ProviderAPIError.operationFailed(
                provider: .namecheap,
                operation: "record replacement",
                message: "the API did not confirm the complete host set"
            )
        }
    }

    private func verifyHosts(
        domain: NamecheapDomain,
        expected: [NamecheapHost],
        operation: String
    ) async throws {
        let expectedCounts = verificationCounts(expected)
        var actualCounts: [NamecheapHostVerificationKey: Int] = [:]
        for attempt in 0 ..< 6 {
            let actual = try await listHosts(domain: domain)
            actualCounts = verificationCounts(actual)
            if actualCounts == expectedCounts {
                return
            }
            if attempt < 5 {
                try await sleep(TimeInterval(attempt + 1))
            }
        }
        let missing = verificationDifference(expected: expectedCounts, actual: actualCounts)
        let unexpected = verificationDifference(expected: actualCounts, actual: expectedCounts)
        throw ProviderAPIError.operationFailed(
            provider: .namecheap,
            operation: operation,
            message: "the write was accepted, but the returned host set did not match; " +
                "missing [\(missing)] unexpected [\(unexpected)]"
        )
    }

    private func verificationCounts(_ hosts: [NamecheapHost]) -> [NamecheapHostVerificationKey: Int] {
        Dictionary(hosts.map { ($0.verificationKey, 1) }, uniquingKeysWith: +)
    }

    private func verificationDifference(
        expected: [NamecheapHostVerificationKey: Int],
        actual: [NamecheapHostVerificationKey: Int]
    ) -> String {
        expected.compactMap { key, count in
            let difference = count - (actual[key] ?? 0)
            return difference > 0 ? "\(difference)x \(key.summary)" : nil
        }
        .sorted()
        .joined(separator: ", ")
    }

    private func tldNames() async throws -> [String] {
        if let cachedTLDs {
            return cachedTLDs
        }
        let root = try await request(command: "namecheap.domains.getTldList")
        let tlds = root.descendants(named: "Tld")
            .compactMap { $0.attribute("Name")?.lowercased() }
            .sorted { $0.count > $1.count }
        guard !tlds.isEmpty else {
            throw ProviderAPIError.invalidResponse(provider: .namecheap)
        }
        cachedTLDs = tlds
        return tlds
    }

    private func domainParts(_ name: String, tlds: [String]) -> (sld: String, tld: String)? {
        let domain = name.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        for tld in tlds {
            let suffix = ".\(tld)"
            guard domain.hasSuffix(suffix) else { continue }
            let sld = String(domain.dropLast(suffix.count))
            if !sld.isEmpty, !sld.contains(".") {
                return (sld, tld)
            }
        }
        return nil
    }

    private func domainParameters(_ domain: NamecheapDomain) -> [String: String] {
        ["SLD": domain.sld, "TLD": domain.tld]
    }

    private func request(
        command: String,
        parameters: [String: String] = [:]
    ) async throws -> ProviderXMLNode {
        let configuration = try configuration()
        let globalParameters = [
            "ApiUser": configuration.username,
            "ApiKey": configuration.apiKey,
            "UserName": configuration.username,
            "ClientIp": configuration.clientIp,
            "Command": command,
        ]
        let requestParameters = globalParameters.merging(parameters, uniquingKeysWith: { _, explicit in explicit })
        var components = URLComponents()
        components.queryItems = requestParameters
            .sorted { $0.key < $1.key }
            .map(URLQueryItem.init)

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await transport.send(request)
        guard let response = response as? HTTPURLResponse else {
            throw ProviderAPIError.invalidResponse(provider: .namecheap)
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw ProviderAPIError.http(
                provider: .namecheap,
                statusCode: response.statusCode,
                message: nil,
                requestId: nil,
                retryAfter: nil
            )
        }

        let root: ProviderXMLNode
        do {
            root = try ProviderXMLNode.parse(data)
        } catch {
            throw ProviderAPIError.decoding(provider: .namecheap, message: error.localizedDescription)
        }
        guard root.attribute("Status")?.caseInsensitiveCompare("OK") == .orderedSame else {
            let messages = root.descendants(named: "Error").map { error in
                [error.attribute("Number"), error.trimmedText].compactMap { $0 }.joined(separator: ": ")
            }
            throw ProviderAPIError.operationFailed(
                provider: .namecheap,
                operation: command,
                message: messages.isEmpty ? "the API returned an error" : messages.joined(separator: "\n")
            )
        }
        return root
    }

    private func configuration() throws -> Configuration {
        let credentials = credentialsProvider()
        guard let username = credentials.username?.trimmed, !username.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .namecheap, field: "API Username")
        }
        guard let apiKey = credentials.apiKey?.trimmed, !apiKey.isEmpty else {
            throw ProviderAPIError.missingCredential(provider: .namecheap, field: "API Key")
        }
        guard let clientIp = credentials.clientIp?.trimmed, InputValidator.validateIPv4Address(clientIp).isValid else {
            throw ProviderAPIError.operationFailed(
                provider: .namecheap,
                operation: "authentication",
                message: "Client IPv4 must be a valid address allowlisted in Namecheap"
            )
        }

        let environment = credentials.environment?.trimmed.lowercased() ?? ""
        let endpoint: URL
        switch environment {
        case "", "production":
            endpoint = URL(string: "https://api.namecheap.com/xml.response")!
        case "sandbox":
            endpoint = URL(string: "https://api.sandbox.namecheap.com/xml.response")!
        default:
            throw ProviderAPIError.operationFailed(
                provider: .namecheap,
                operation: "configuration",
                message: "API Environment must be production or sandbox"
            )
        }
        return Configuration(username: username, apiKey: apiKey, clientIp: clientIp, endpoint: endpoint)
    }
}
