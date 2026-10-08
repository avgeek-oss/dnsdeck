import Foundation

struct SpaceshipDomainListResponse: Decodable {
    let items: [SpaceshipDomain]
    let total: Int
}

struct SpaceshipDomain: Codable, Hashable {
    struct Nameservers: Codable, Hashable {
        let provider: String?
        let hosts: [String]
    }

    let name: String
    let unicodeName: String?
    let autoRenew: Bool?
    let registrationDate: String?
    let expirationDate: String?
    let lifecycleStatus: String?
    let verificationStatus: String?
    let nameservers: Nameservers?

    func snapshot() -> ProviderZoneSnapshot {
        var metadata: [String: String] = [:]
        if let autoRenew { metadata["autoRenew"] = String(autoRenew) }
        if let registrationDate { metadata["registrationDate"] = registrationDate }
        if let expirationDate { metadata["expirationDate"] = expirationDate }
        if let verificationStatus { metadata["verificationStatus"] = verificationStatus }
        if let nameserverProvider = nameservers?.provider { metadata["nameserverProvider"] = nameserverProvider }
        return ProviderZoneSnapshot(
            id: name,
            name: unicodeName ?? name,
            nameservers: nameservers?.hosts ?? [],
            status: lifecycleStatus,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct SpaceshipNameserverUpdateRequest: Codable, Equatable {
    let provider: String
    let hosts: [String]
}

struct SpaceshipRecordListResponse: Decodable {
    let items: [SpaceshipDNSRecord]
    let total: Int
}

struct SpaceshipRecordGroup: Codable, Hashable {
    let type: String
}

enum SpaceshipPort: Codable, Hashable {
    case number(Int)
    case label(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else {
            self = try .label(container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .number(value): try container.encode(value)
        case let .label(value): try container.encode(value)
        }
    }

    var displayValue: String {
        switch self {
        case let .number(value): String(value)
        case let .label(value): value
        }
    }
}

struct SpaceshipDNSRecord: Codable, Hashable {
    let type: String
    var name: String
    var ttl: Int? = nil
    var group: SpaceshipRecordGroup? = nil
    var address: String? = nil
    var aliasName: String? = nil
    var flag: Int? = nil
    var tag: String? = nil
    var value: String? = nil
    var cname: String? = nil
    var port: SpaceshipPort? = nil
    var scheme: String? = nil
    var svcPriority: Int? = nil
    var targetName: String? = nil
    var svcParams: String? = nil
    var exchange: String? = nil
    var preference: Int? = nil
    var nameserver: String? = nil
    var pointer: String? = nil
    var service: String? = nil
    var `protocol`: String? = nil
    var priority: Int? = nil
    var weight: Int? = nil
    var target: String? = nil
    var usage: Int? = nil
    var selector: Int? = nil
    var matching: Int? = nil
    var associationData: String? = nil

    func snapshot(zoneName: String) -> ProviderRecordSnapshot {
        let mutation = mutation(ttl: ttl)
        let protected = group?.type != "custom"
        return ProviderRecordSnapshot(
            id: mutation.identifier,
            name: displayName(zoneName: zoneName),
            type: type,
            values: [displayContent],
            ttl: ttl,
            priority: displayPriority,
            aliasTarget: type == "ALIAS" ? aliasName.map {
                DNSAliasTarget(name: $0, zoneId: nil, evaluateTargetHealth: nil)
            } : nil,
            metadata: [
                "group": group?.type ?? "",
                "isProtected": String(protected),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }

    func mutation(ttl: Int?) -> SpaceshipRecordMutation {
        var mutation = self
        mutation.ttl = ttl
        mutation.group = nil
        return mutation
    }

    var displayContent: String {
        switch type.uppercased() {
        case "A", "AAAA": address ?? ""
        case "ALIAS": aliasName ?? ""
        case "CAA": "\(flag ?? 0) \(tag ?? "") \(value ?? "")"
        case "CNAME": cname ?? ""
        case "HTTPS", "SVCB": [String(svcPriority ?? 0), targetName ?? ".", svcParams ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        case "MX": exchange ?? ""
        case "NS": nameserver ?? ""
        case "PTR": pointer ?? ""
        case "SRV": "\(weight ?? 0) \(port?.displayValue ?? "0") \(target ?? "")"
        case "TLSA": "\(usage ?? 0) \(selector ?? 0) \(matching ?? 0) \(associationData ?? "")"
        case "TXT": value ?? ""
        default: value ?? address ?? target ?? ""
        }
    }

    private var displayPriority: Int? {
        switch type.uppercased() {
        case "MX": preference
        case "SRV": priority
        default: nil
        }
    }

    private func displayName(zoneName: String) -> String {
        let base = spaceshipAbsoluteName(name, zoneName: zoneName)
        switch type.uppercased() {
        case "SRV": return spaceshipPrefixedName([service, `protocol`], base: base)
        case "TLSA": return spaceshipPrefixedName([port?.displayValue, `protocol`], base: base)
        case "HTTPS", "SVCB": return spaceshipPrefixedName([port?.displayValue, scheme], base: base)
        default: return base
        }
    }
}

typealias SpaceshipRecordMutation = SpaceshipDNSRecord

extension SpaceshipDNSRecord {
    var identifier: String {
        let canonical = comparisonData.base64EncodedString()
        return "\(type.uppercased())|\(canonical)"
    }

    var comparisonData: Data {
        var value = self
        value.ttl = nil
        value.group = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = (try? encoder.encode(value)) ?? Data()
        guard type.uppercased() != "TXT", let text = String(data: encoded, encoding: .utf8) else {
            return encoded
        }
        return Data(text.lowercased().utf8)
    }

    func replacingTTL(_ ttl: Int?) -> SpaceshipRecordMutation {
        var mutation = self
        mutation.ttl = ttl
        mutation.group = nil
        return mutation
    }
}

struct SpaceshipSaveRecordsRequest: Codable, Equatable {
    let force: Bool
    let items: [SpaceshipRecordMutation]
}

extension CreateProviderRecordRequest {
    func toSpaceshipMutations(zoneName: String) throws -> [SpaceshipRecordMutation] {
        let contents = values ?? [recordData?.flatContent ?? aliasTarget ?? content]
        return try contents.map {
            try SpaceshipRecordMutation.make(
                type: type,
                name: name,
                content: $0,
                ttl: DNSProvider.spaceship.getEffectiveTTL(ttl),
                priority: priority,
                recordData: recordData,
                aliasTarget: aliasTarget,
                zoneName: zoneName
            )
        }
    }
}

extension UpdateProviderRecordRequest {
    func toSpaceshipMutation(zoneName: String, existing: SpaceshipDNSRecord) throws -> SpaceshipRecordMutation {
        guard values == nil || values?.count == 1 else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .spaceship,
                type: type ?? existing.type,
                message: "individual Spaceship record edits accept exactly one value"
            )
        }

        let existingSnapshot = existing.snapshot(zoneName: zoneName)
        let hasIdentityEdit = name != nil || type != nil || content != nil || values != nil || aliasTarget != nil ||
            recordData != nil || priority != nil
        if !hasIdentityEdit {
            return existing.mutation(ttl: DNSProvider.spaceship.normalizeTTL(ttl ?? existing.ttl))
        }

        return try SpaceshipRecordMutation.make(
            type: type ?? existing.type,
            name: name ?? existingSnapshot.name,
            content: values?.first ?? recordData?.flatContent ?? content ?? existingSnapshot.content,
            ttl: DNSProvider.spaceship.normalizeTTL(ttl ?? existing.ttl),
            priority: priority ?? existingSnapshot.priority,
            recordData: recordData,
            aliasTarget: aliasTarget ?? existing.aliasName,
            zoneName: zoneName
        )
    }
}

private extension SpaceshipRecordMutation {
    static func make(
        type rawType: String,
        name rawName: String,
        content rawContent: String,
        ttl: Int?,
        priority: Int?,
        recordData: RecordData?,
        aliasTarget: String?,
        zoneName: String
    ) throws -> SpaceshipRecordMutation {
        let type = rawType.uppercased()
        try validateSpaceshipRecordType(type)
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        var mutation = SpaceshipRecordMutation(
            type: type,
            name: ProviderDNSName.relativeAtCaseInsensitive(rawName, zoneName: zoneName),
            ttl: ttl
        )

        switch type {
        case "A", "AAAA": mutation.address = content
        case "ALIAS": mutation.aliasName = aliasTarget ?? content
        case "CAA":
            let parts = content.split(maxSplits: 2, whereSeparator: \Character.isWhitespace).map(String.init)
            let flag = recordData?.flags ?? parts.first.flatMap(Int.init)
            let tag = recordData?.tag ?? parts.dropFirst().first
            let value = recordData?.value ?? parts.last
            guard let flag, [0, 128].contains(flag), let tag, let value, parts.count >= 3 || recordData != nil else {
                throw invalidSpaceshipContent(type, "expected flag, tag, and value; flag must be 0 or 128")
            }
            mutation.flag = flag
            mutation.tag = tag
            mutation.value = value
        case "CNAME": mutation.cname = content
        case "HTTPS", "SVCB":
            let parts = content.split(maxSplits: 2, whereSeparator: \Character.isWhitespace).map(String.init)
            guard parts.count >= 2, let svcPriority = Int(parts[0]), (0 ... 65535).contains(svcPriority) else {
                throw invalidSpaceshipContent(type, "expected priority, target name, and optional service parameters")
            }
            let prefix = spaceshipServicePrefix(from: mutation.name, allowedScheme: type == "HTTPS" ? "_https" : nil)
            mutation.name = prefix.owner
            mutation.port = prefix.port
            mutation.scheme = prefix.scheme
            mutation.svcPriority = svcPriority
            mutation.targetName = parts[1]
            mutation.svcParams = parts.count == 3 ? parts[2] : ""
        case "MX":
            let parts = content.split(maxSplits: 1, whereSeparator: \Character.isWhitespace).map(String.init)
            let embeddedPriority = parts.count == 2 ? Int(parts[0]) : nil
            let preference = recordData?.priority ?? priority ?? embeddedPriority ?? 0
            guard (0 ... 65535).contains(preference) else {
                throw invalidSpaceshipContent(type, "preference must be between 0 and 65535")
            }
            mutation.exchange = embeddedPriority == nil ? content : parts[1]
            mutation.preference = preference
        case "NS": mutation.nameserver = content
        case "PTR": mutation.pointer = content
        case "SRV":
            let prefix = try spaceshipRequiredPrefix(
                from: mutation.name,
                first: recordData?.service,
                second: recordData?.proto,
                type: type
            )
            mutation.name = prefix.owner
            let parts = content.split(whereSeparator: \Character.isWhitespace).map(String.init)
            let parsed: (Int, Int, Int, String)? = if let recordData,
                                                      let resolvedPriority = recordData.priority ?? priority,
                                                      let weight = recordData.weight,
                                                      let port = recordData.port,
                                                      let target = recordData.target
            {
                (resolvedPriority, weight, port, target)
            } else if parts.count >= 4, let resolvedPriority = Int(parts[0]), let weight = Int(parts[1]),
                      let port = Int(parts[2])
            {
                (resolvedPriority, weight, port, parts.dropFirst(3).joined(separator: " "))
            } else if parts.count >= 3, let weight = Int(parts[0]), let port = Int(parts[1]) {
                (priority ?? 0, weight, port, parts.dropFirst(2).joined(separator: " "))
            } else {
                nil
            }
            guard let parsed, (0 ... 65535).contains(parsed.0), (0 ... 65535).contains(parsed.1),
                  (1 ... 65535).contains(parsed.2)
            else {
                throw invalidSpaceshipContent(type, "expected priority, weight, port, and target")
            }
            mutation.service = prefix.first
            mutation.protocol = prefix.second
            mutation.priority = parsed.0
            mutation.weight = parsed.1
            mutation.port = .number(parsed.2)
            mutation.target = parsed.3
        case "TLSA":
            let prefix = try spaceshipRequiredPrefix(from: mutation.name, first: nil, second: nil, type: type)
            mutation.name = prefix.owner
            let parts = content.split(maxSplits: 3, whereSeparator: \Character.isWhitespace).map(String.init)
            let associationData = parts.count == 4
                ? parts[3].filter { !$0.isWhitespace }.lowercased()
                : ""
            guard parts.count == 4, let usage = Int(parts[0]), let selector = Int(parts[1]),
                  let matching = Int(parts[2]), (0 ... 255).contains(usage), (0 ... 255).contains(selector),
                  (0 ... 255).contains(matching), (64 ... 65535).contains(associationData.count),
                  associationData.count.isMultiple(of: 2), associationData.allSatisfy(\.isHexDigit)
            else {
                throw invalidSpaceshipContent(
                    type,
                    "expected usage, selector, matching type, and at least 64 hexadecimal association-data characters"
                )
            }
            mutation.port = .label(prefix.first)
            mutation.protocol = prefix.second
            mutation.usage = usage
            mutation.selector = selector
            mutation.matching = matching
            mutation.associationData = associationData
        case "TXT": mutation.value = rawContent
        default: break
        }

        return mutation
    }
}

private func validateSpaceshipRecordType(_ type: String) throws {
    guard DNSProvider.spaceship.capabilities.canEdit(recordType: type) else {
        throw invalidSpaceshipContent(type, "the record type is unsupported by the Spaceship API")
    }
}

private func invalidSpaceshipContent(_ type: String, _ message: String) -> ProviderAPIError {
    .invalidRecordContent(provider: .spaceship, type: type, message: message)
}

private func spaceshipAbsoluteName(_ name: String, zoneName: String) -> String {
    let relative = ProviderDNSName.relativeAtCaseInsensitive(name, zoneName: zoneName)
    return relative == "@" ? zoneName : "\(relative).\(zoneName)"
}

private func spaceshipPrefixedName(_ prefixes: [String?], base: String) -> String {
    (prefixes.compactMap { $0 }.filter { !$0.isEmpty } + [base]).joined(separator: ".")
}

private func spaceshipRequiredPrefix(
    from relativeName: String,
    first explicitFirst: String?,
    second explicitSecond: String?,
    type: String
) throws -> (first: String, second: String, owner: String) {
    if let explicitFirst, let explicitSecond {
        return (explicitFirst, explicitSecond, spaceshipStripPrefix(relativeName, [explicitFirst, explicitSecond]))
    }
    let labels = relativeName.split(separator: ".").map(String.init)
    guard labels.count >= 2, labels[0].hasPrefix("_"), labels[1].hasPrefix("_") else {
        throw invalidSpaceshipContent(type, "record name must begin with two underscore-prefixed labels")
    }
    return (labels[0], labels[1], spaceshipNonEmpty(labels.dropFirst(2).joined(separator: ".")) ?? "@")
}

private func spaceshipServicePrefix(
    from relativeName: String,
    allowedScheme: String?
) -> (port: SpaceshipPort?, scheme: String?, owner: String) {
    let labels = relativeName.split(separator: ".").map(String.init)
    guard labels.count >= 2, labels[0] == "*" || labels[0].hasPrefix("_"), labels[1].hasPrefix("_") else {
        return (nil, nil, relativeName)
    }
    guard allowedScheme == nil || labels[1] == allowedScheme else { return (nil, nil, relativeName) }
    return (.label(labels[0]), labels[1], spaceshipNonEmpty(labels.dropFirst(2).joined(separator: ".")) ?? "@")
}

private func spaceshipStripPrefix(_ relativeName: String, _ prefixes: [String]) -> String {
    let labels = relativeName.split(separator: ".").map(String.init)
    guard labels.starts(with: prefixes) else { return relativeName }
    return spaceshipNonEmpty(labels.dropFirst(prefixes.count).joined(separator: ".")) ?? "@"
}

private func spaceshipNonEmpty(_ value: String) -> String? {
    value.isEmpty ? nil : value
}
