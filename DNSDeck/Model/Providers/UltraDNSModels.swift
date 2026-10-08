import Foundation

struct UltraDNSZoneListResponse: Decodable {
    let cursorInfo: UltraDNSCursorInfo?
    let zones: [UltraDNSZone]
}

struct UltraDNSCursorInfo: Codable, Hashable {
    let next: String?
}

struct UltraDNSZone: Codable, Hashable {
    let properties: UltraDNSZoneProperties
    let registrarInfo: UltraDNSRegistrarInfo?

    var name: String {
        ultraDNSWithoutTrailingDot(properties.name)
    }

    var isWritable: Bool {
        properties.type.uppercased() == "PRIMARY" && properties.status?.uppercased() != "SUSPENDED"
    }

    func snapshot() -> ProviderZoneSnapshot {
        let nameServers = registrarInfo?.nameServers
        return ProviderZoneSnapshot(
            id: properties.name,
            name: name,
            nameservers: (nameServers?.ok ?? []) + (nameServers?.missing ?? []),
            status: properties.type.lowercased(),
            metadata: [
                "accountName": properties.accountName ?? "",
                "dnssecStatus": properties.dnssecStatus ?? "",
                "isWritable": String(isWritable),
                "status": properties.status ?? "",
                "ultra2": String(properties.ultra2 ?? false),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct UltraDNSZoneProperties: Codable, Hashable {
    let name: String
    let accountName: String?
    let owner: String?
    let type: String
    let dnssecStatus: String?
    let status: String?
    let ultra2: Bool?
}

struct UltraDNSRegistrarInfo: Codable, Hashable {
    let nameServers: UltraDNSNameServers?
}

struct UltraDNSNameServers: Codable, Hashable {
    let ok: [String]?
    let unknown: [String]?
    let missing: [String]?
}

struct UltraDNSRRSetListResponse: Decodable {
    let zoneName: String?
    let rrSets: [UltraDNSRRSet]
    let resultInfo: UltraDNSResultInfo?

    enum CodingKeys: String, CodingKey {
        case zoneName, resultInfo
        case rrSets
    }
}

struct UltraDNSResultInfo: Codable, Hashable {
    let totalCount: Int
    let offset: Int
    let returnedCount: Int
}

struct UltraDNSRRSet: Codable, Hashable {
    let ownerName: String
    let rrtype: String
    let ttl: Int
    let rdata: [String]
    let profile: ProviderJSONValue?
    let systemGenerated: [Bool]?
    let ultra2SystemGenerated: [Bool]?

    var type: String {
        rrtype.split(whereSeparator: \Character.isWhitespace).first.map(String.init)?.uppercased() ?? rrtype
            .uppercased()
    }

    var isProtected: Bool {
        profile != nil || systemGenerated?.contains(true) == true || ultra2SystemGenerated?.contains(true) == true ||
            !DNSProvider.ultraDNS.capabilities.canEdit(recordType: type)
    }

    func snapshot(zoneName: String) -> ProviderRecordSnapshot {
        let values = type == "TXT" ? rdata.map(ultraDNSDisplayTXT) : rdata
        let priorities = ["MX", "SRV"].contains(type) ? rdata.compactMap(ProviderRecordValue.priority) : []
        return ProviderRecordSnapshot(
            id: "\(ownerName.lowercased())|\(type)",
            name: ultraDNSRelativeName(ownerName, zoneName: zoneName),
            type: type,
            values: type == "MX" ? values.map(ProviderRecordValue.removingPriority) : values,
            ttl: ttl,
            priority: Set(priorities).count == 1 ? priorities.first : nil,
            routingPolicy: profile == nil
                ? nil
                : DNSRecordRoutingPolicy(
                    identifier: nil,
                    weight: nil,
                    region: nil,
                    continent: nil,
                    country: nil,
                    subdivision: nil,
                    failover: nil,
                    multiValueAnswer: rdata.count > 1,
                    healthCheckId: nil
                ),
            metadata: [
                "hasAdvancedConfiguration": String(profile != nil),
                "isProtected": String(isProtected),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct UltraDNSRRSetWrite: Codable, Equatable {
    let ttl: Int
    let rdata: [String]
}

struct UltraDNSAccessTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: UltraDNSFlexibleInt

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

enum UltraDNSFlexibleInt: Decodable {
    case value(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) { self = .value(value) }
        else { self = try .value(Int(container.decode(String.self)) ?? 0) }
    }

    var intValue: Int {
        if case let .value(value) = self { return value }
        return 0
    }
}

extension CreateProviderRecordRequest {
    func toUltraDNSRRSet(zoneName: String) throws -> (owner: String, type: String, write: UltraDNSRRSetWrite) {
        let resolvedType = type.uppercased()
        try DNSProvider.ultraDNS.validateEditableRecordType(resolvedType)
        let rawValues = values ?? [aliasTarget ?? recordData?.flatContent ?? content]
        return (
            ultraDNSAbsoluteName(name, zoneName: zoneName),
            resolvedType,
            UltraDNSRRSetWrite(
                ttl: DNSProvider.ultraDNS.getEffectiveTTL(ttl) ?? DNSProvider.ultraDNS.defaultTTL,
                rdata: ultraDNSWriteValues(type: resolvedType, values: rawValues, priority: priority)
            )
        )
    }
}

extension UpdateProviderRecordRequest {
    func toUltraDNSRRSet(
        zoneName: String,
        existing: UltraDNSRRSet
    ) throws -> (owner: String, type: String, write: UltraDNSRRSetWrite) {
        let resolvedType = (type ?? existing.type).uppercased()
        try DNSProvider.ultraDNS.validateEditableRecordType(resolvedType)
        let typeChanged = resolvedType != existing.type.uppercased()
        let rawValues = values ?? [aliasTarget ?? recordData?.flatContent ?? content].compactMap { $0 }
        if typeChanged, rawValues.isEmpty {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ultraDNS,
                type: resolvedType,
                message: "record type changes require replacement values"
            )
        }
        let resolvedValues = rawValues.isEmpty ? existing.rdata : rawValues
        return (
            ultraDNSAbsoluteName(name ?? existing.ownerName, zoneName: zoneName),
            resolvedType,
            UltraDNSRRSetWrite(
                ttl: DNSProvider.ultraDNS.getEffectiveTTL(ttl ?? existing.ttl) ?? existing.ttl,
                rdata: rawValues.isEmpty
                    ? existing.rdata
                    : ultraDNSWriteValues(
                        type: resolvedType,
                        values: resolvedValues,
                        priority: priority,
                        existingValues: existing.rdata
                    )
            )
        )
    }
}

private func ultraDNSWriteValues(
    type: String,
    values: [String],
    priority: Int?,
    existingValues: [String] = []
) -> [String] {
    guard type == "MX" else { return values }
    return values.enumerated().map { index, value in
        guard ProviderRecordValue.priority(value) == nil else { return value }
        let existingPriority = existingValues.indices.contains(index)
            ? ProviderRecordValue.priority(existingValues[index])
            : nil
        return "\(priority ?? existingPriority ?? 10) \(value)"
    }
}

private func ultraDNSAbsoluteName(_ name: String, zoneName: String) -> String {
    let value = ultraDNSWithoutTrailingDot(name.trimmingCharacters(in: .whitespacesAndNewlines))
    let zone = ultraDNSWithoutTrailingDot(zoneName)
    if value.isEmpty || value == "@" || value.caseInsensitiveCompare(zone) == .orderedSame { return "\(zone)." }
    if value.lowercased().hasSuffix(".\(zone.lowercased())") { return "\(value)." }
    return "\(value).\(zone)."
}

private func ultraDNSRelativeName(_ name: String, zoneName: String) -> String {
    let value = ultraDNSWithoutTrailingDot(name)
    let zone = ultraDNSWithoutTrailingDot(zoneName)
    if value.caseInsensitiveCompare(zone) == .orderedSame { return "@" }
    let suffix = ".\(zone)"
    return value.lowercased().hasSuffix(suffix.lowercased()) ? String(value.dropLast(suffix.count)) : value
}

private func ultraDNSWithoutTrailingDot(_ value: String) -> String {
    value.hasSuffix(".") ? String(value.dropLast()) : value
}

private func ultraDNSDisplayTXT(_ value: String) -> String {
    guard value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
    return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\" \"", with: "")
}
