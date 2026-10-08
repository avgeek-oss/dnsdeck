import Foundation

struct IBMNS1Zone: Codable, Hashable {
    let id: String?
    let zone: String
    let dnsServers: [String]?
    let ttl: Int?
    let nxTTL: Int?
    let serial: Int?
    let link: String?
    let networks: [Int]?
    let records: [IBMNS1ZoneRecord]?
    let secondary: IBMNS1Secondary?
    let dnssec: Bool?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, zone, ttl, serial, link, networks, records, secondary, dnssec, tags
        case dnsServers = "dns_servers"
        case nxTTL = "nx_ttl"
    }

    var isWritable: Bool {
        link?.isEmpty != false && secondary?.enabled != true
    }

    func snapshot() -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: id ?? zone,
            name: zone,
            nameservers: dnsServers ?? [],
            status: secondary?.enabled == true ? "secondary" : (link?.isEmpty == false ? "linked" : "primary"),
            metadata: [
                "dnssec": String(dnssec ?? false),
                "isWritable": String(isWritable),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct IBMNS1Secondary: Codable, Hashable {
    let enabled: Bool
    let status: String?
    let expired: Bool?
}

struct IBMNS1ZoneRecord: Codable, Hashable {
    let domain: String
    let id: String?
    let link: String?
    let ttl: Int
    let type: String

    enum CodingKeys: String, CodingKey {
        case domain, id, link, ttl, type
    }
}

struct IBMNS1Record: Codable, Hashable {
    let id: String?
    let zone: String
    let domain: String
    let type: String
    let link: String?
    let ttl: Int
    let answers: [IBMNS1Answer]
    let filters: [ProviderJSONValue]
    let regions: [String: ProviderJSONValue]
    let meta: [String: ProviderJSONValue]?
    let tags: [String: String]?
    let blockedTags: [String]?
    let overrideTTL: Bool?
    let overrideAddressRecords: Bool?
    let useClientSubnet: Bool?

    enum CodingKeys: String, CodingKey {
        case id, zone, domain, type, link, ttl, answers, filters, regions, meta, tags
        case blockedTags = "blocked_tags"
        case overrideAddressRecords = "override_address_records"
        case overrideTTL = "override_ttl"
        case useClientSubnet = "use_client_subnet"
    }

    var hasAdvancedConfiguration: Bool {
        !filters.isEmpty || !regions.isEmpty || answers.contains(where: \.hasMetadata)
    }

    func snapshot() -> ProviderRecordSnapshot {
        let resolvedType = type.uppercased()
        let nativeValues = answers.map { $0.answer.map(\.displayString).joined(separator: " ") }
        let displayValues: [String] = switch resolvedType {
        case "MX": nativeValues.map(ProviderRecordValue.removingPriority)
        default: nativeValues
        }
        let priorities = ["MX", "SRV"].contains(resolvedType) ? nativeValues
            .compactMap(ProviderRecordValue.priority) : []
        let isProtected = link?.isEmpty == false
        return ProviderRecordSnapshot(
            id: id ?? "\(domain.lowercased())|\(resolvedType)",
            name: ProviderDNSName.relativeAtCaseInsensitive(domain, zoneName: zone),
            type: resolvedType,
            values: displayValues,
            ttl: ttl,
            priority: Set(priorities).count == 1 ? priorities.first : nil,
            aliasTarget: resolvedType == "ALIAS"
                ? displayValues.first.map { DNSAliasTarget(name: $0, zoneId: nil, evaluateTargetHealth: nil) }
                : nil,
            routingPolicy: hasAdvancedConfiguration
                ? DNSRecordRoutingPolicy(
                    identifier: id,
                    weight: nil,
                    region: nil,
                    continent: nil,
                    country: nil,
                    subdivision: nil,
                    failover: nil,
                    multiValueAnswer: answers.count > 1,
                    healthCheckId: nil
                )
                : nil,
            metadata: [
                "hasAdvancedConfiguration": String(hasAdvancedConfiguration),
                "isProtected": String(isProtected),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct IBMNS1Answer: Codable, Hashable {
    let id: String?
    let answer: [ProviderJSONValue]
    let meta: [String: ProviderJSONValue]?
    let feeds: [ProviderJSONValue]?
    let region: String?

    var hasMetadata: Bool {
        meta?.isEmpty == false || feeds?.isEmpty == false || region?.isEmpty == false
    }
}

struct IBMNS1CreateZoneRequest: Codable, Equatable {
    let zone: String
}

struct IBMNS1RecordMutation: Codable, Equatable {
    let zone: String
    let domain: String
    let type: String
    let ttl: Int
    let answers: [IBMNS1Answer]
    let filters: [ProviderJSONValue]
    let regions: [String: ProviderJSONValue]
    let meta: [String: ProviderJSONValue]?
    let tags: [String: String]?
    let blockedTags: [String]?
    let overrideTTL: Bool?
    let overrideAddressRecords: Bool?
    let useClientSubnet: Bool?

    enum CodingKeys: String, CodingKey {
        case zone, domain, type, ttl, answers, filters, regions, meta, tags
        case blockedTags = "blocked_tags"
        case overrideAddressRecords = "override_address_records"
        case overrideTTL = "override_ttl"
        case useClientSubnet = "use_client_subnet"
    }
}

extension IBMNS1Record {
    func mutation() -> IBMNS1RecordMutation {
        let hasDDITags = tags?.isEmpty == false || blockedTags?.isEmpty == false
        return IBMNS1RecordMutation(
            zone: zone,
            domain: domain,
            type: type,
            ttl: ttl,
            answers: answers,
            filters: filters,
            regions: regions,
            meta: meta,
            tags: hasDDITags ? (tags ?? [:]) : nil,
            blockedTags: hasDDITags ? (blockedTags ?? []) : nil,
            overrideTTL: overrideTTL,
            overrideAddressRecords: overrideAddressRecords,
            useClientSubnet: useClientSubnet
        )
    }
}

extension CreateProviderRecordRequest {
    func toIBMNS1Record(zoneName: String) throws -> IBMNS1Record {
        let resolvedType = type.uppercased()
        try DNSProvider.ibmNS1.validateEditableRecordType(resolvedType)
        let rawValues = values ?? [aliasTarget ?? recordData?.flatContent ?? content]
        return try IBMNS1Record(
            id: nil,
            zone: zoneName,
            domain: ibmNS1AbsoluteName(name, zoneName: zoneName),
            type: resolvedType,
            link: nil,
            ttl: DNSProvider.ibmNS1.getEffectiveTTL(ttl) ?? DNSProvider.ibmNS1.defaultTTL,
            answers: rawValues.map {
                try IBMNS1Answer(
                    id: nil,
                    answer: ibmNS1Answer(type: resolvedType, value: $0, priority: priority, recordData: recordData),
                    meta: nil,
                    feeds: nil,
                    region: nil
                )
            },
            filters: [],
            regions: [:],
            meta: nil,
            tags: nil,
            blockedTags: nil,
            overrideTTL: nil,
            overrideAddressRecords: nil,
            useClientSubnet: nil
        )
    }
}

extension UpdateProviderRecordRequest {
    func toIBMNS1Record(zoneName: String, existing: IBMNS1Record) throws -> IBMNS1Record {
        let resolvedType = (type ?? existing.type).uppercased()
        try DNSProvider.ibmNS1.validateEditableRecordType(resolvedType)
        let resolvedDomain = ibmNS1AbsoluteName(name ?? existing.domain, zoneName: zoneName)
        let typeChanged = resolvedType != existing.type.uppercased()
        let hasReplacementValues = values != nil || recordData != nil || content != nil || aliasTarget != nil
        let hasPriorityEdit = priority != nil && ["MX", "SRV"].contains(resolvedType)
        let hasAnswerEdits = hasReplacementValues || hasPriorityEdit || typeChanged
        let hasConfigurationEdits = name != nil || hasAnswerEdits
        if typeChanged, !hasReplacementValues {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ibmNS1,
                type: resolvedType,
                message: "record type changes require replacement values"
            )
        }
        if hasConfigurationEdits, existing.hasAdvancedConfiguration {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ibmNS1,
                type: resolvedType,
                message: "answers with Filter Chain metadata must be edited in NS1 Connect"
            )
        }
        let answers: [IBMNS1Answer]
        if hasReplacementValues {
            let rawValues = values ?? [aliasTarget ?? recordData?.flatContent ?? content ?? ""]
            answers = try rawValues.map {
                try IBMNS1Answer(
                    id: nil,
                    answer: ibmNS1Answer(
                        type: resolvedType,
                        value: $0,
                        priority: priority ?? existing.snapshot().priority,
                        recordData: recordData
                    ),
                    meta: nil,
                    feeds: nil,
                    region: nil
                )
            }
        } else if let priority, hasPriorityEdit {
            answers = try existing.answers.map { try ibmNS1Answer(
                $0,
                replacingPriorityWith: priority,
                type: resolvedType
            ) }
        } else {
            answers = existing.answers
        }
        return IBMNS1Record(
            id: existing.id,
            zone: zoneName,
            domain: resolvedDomain,
            type: resolvedType,
            link: existing.link,
            ttl: DNSProvider.ibmNS1.getEffectiveTTL(ttl ?? existing.ttl) ?? existing.ttl,
            answers: answers,
            filters: existing.filters,
            regions: existing.regions,
            meta: existing.meta,
            tags: existing.tags,
            blockedTags: existing.blockedTags,
            overrideTTL: existing.overrideTTL,
            overrideAddressRecords: existing.overrideAddressRecords,
            useClientSubnet: existing.useClientSubnet
        )
    }
}

private func ibmNS1Answer(
    _ existing: IBMNS1Answer,
    replacingPriorityWith priority: Int,
    type: String
) throws -> IBMNS1Answer {
    guard ["MX", "SRV"].contains(type), !existing.answer.isEmpty else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .ibmNS1,
            type: type,
            message: "priority is only supported for MX and SRV answers"
        )
    }
    var answer = existing.answer
    answer[0] = .number(Double(priority))
    return IBMNS1Answer(
        id: existing.id,
        answer: answer,
        meta: existing.meta,
        feeds: existing.feeds,
        region: existing.region
    )
}

private func ibmNS1Answer(
    type: String,
    value: String,
    priority: Int?,
    recordData: RecordData?
) throws -> [ProviderJSONValue] {
    switch type {
    case "MX":
        let parts = value.split(whereSeparator: \Character.isWhitespace)
        if parts.first.flatMap({ Int($0) }) != nil {
            return [.number(Double(Int(parts[0]) ?? 10)), .string(parts.dropFirst().joined(separator: " "))]
        }
        return [.number(Double(recordData?.priority ?? priority ?? 10)), .string(recordData?.target ?? value)]
    case "SRV":
        let raw = recordData?.flatContent ?? value
        let parts = raw.split(whereSeparator: \Character.isWhitespace)
        guard parts.count >= 4, parts.prefix(3).allSatisfy({ Int($0) != nil }) else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ibmNS1,
                type: type,
                message: "expected priority, weight, port, and target"
            )
        }
        return [
            .number(Double(Int(parts[0]) ?? 0)),
            .number(Double(Int(parts[1]) ?? 0)),
            .number(Double(Int(parts[2]) ?? 0)),
            .string(parts.dropFirst(3).joined(separator: " ")),
        ]
    case "CAA":
        let parts = value.split(maxSplits: 2, whereSeparator: \Character.isWhitespace)
        guard parts.count == 3, let flags = Int(parts[0]) else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ibmNS1,
                type: type,
                message: "expected flags, tag, and value"
            )
        }
        return [.number(Double(flags)), .string(String(parts[1])), .string(String(parts[2]))]
    case "A", "AAAA", "ALIAS", "CNAME", "DNAME", "OPENPGPKEY", "PTR", "SMIMEA", "SPF", "TXT":
        return [.string(value)]
    case "HTTPS", "SVCB":
        let parts = ibmNS1Fields(value, maxSplits: 2)
        guard parts.count >= 2 else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ibmNS1,
                type: type,
                message: "expected priority, target, and optional service parameters"
            )
        }
        return parts.map(ProviderJSONValue.string)
    default:
        let parts = ibmNS1Fields(value)
        guard !parts.isEmpty else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ibmNS1,
                type: type,
                message: "record content cannot be empty"
            )
        }
        return parts.map(ProviderJSONValue.string)
    }
}

private func ibmNS1Fields(_ value: String, maxSplits: Int = .max) -> [String] {
    var fields: [String] = []
    var field = ""
    var quoted = false
    var escaping = false
    var splits = 0
    for character in value {
        if escaping {
            field.append(character)
            escaping = false
        } else if character == "\\" {
            escaping = true
        } else if character == "\"" {
            quoted.toggle()
        } else if character.isWhitespace, !quoted, !field.isEmpty, splits < maxSplits {
            fields.append(field)
            field = ""
            splits += 1
        } else if !character.isWhitespace || quoted || !field.isEmpty {
            field.append(character)
        }
    }
    if escaping { field.append("\\") }
    if !field.isEmpty { fields.append(field) }
    return fields
}

private func ibmNS1AbsoluteName(_ name: String, zoneName: String) -> String {
    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let zone = zoneName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    if value.isEmpty || value == "@" || value == zone { return zone }
    return value.hasSuffix(".\(zone)") ? value : "\(value).\(zone)"
}
