import Foundation

struct PowerDNSZone: Codable, Hashable {
    let id: String
    let name: String
    let kind: String
    let url: String?
    let rrsets: [PowerDNSRRset]?
    let serial: Int?
    let masters: [String]?
    let dnssec: Bool?
    let account: String?
    let catalog: String?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, url, rrsets, serial, masters, dnssec, account, catalog
    }

    var isWritable: Bool {
        ["NATIVE", "MASTER"].contains(kind.uppercased())
    }

    func snapshot() -> ProviderZoneSnapshot {
        let normalizedName = name.hasSuffix(".") ? String(name.dropLast()) : name
        let apexNS = rrsets?.first {
            $0.type.uppercased() == "NS" && powerDNSNamesEqual($0.name, name)
        }?.records.filter { !$0.disabled }.map(\.content) ?? []
        return ProviderZoneSnapshot(
            id: id,
            name: normalizedName,
            nameservers: apexNS,
            status: kind,
            metadata: [
                "dnssec": String(dnssec ?? false),
                "isWritable": String(isWritable),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct PowerDNSRRset: Codable, Hashable {
    let name: String
    let type: String
    let ttl: Int
    let records: [PowerDNSRecord]
    let comments: [PowerDNSComment]?
}

struct PowerDNSRecord: Codable, Hashable {
    let content: String
    let disabled: Bool
}

struct PowerDNSComment: Codable, Hashable {
    let content: String?
    let account: String?
    let modifiedAt: Int?

    enum CodingKeys: String, CodingKey {
        case content, account
        case modifiedAt = "modified_at"
    }
}

extension PowerDNSRRset {
    func snapshot(zoneName: String) -> ProviderRecordSnapshot {
        let resolvedType = type.uppercased()
        let nativeValues = records.map(\.content)
        let displayValues: [String] = switch resolvedType {
        case "TXT": nativeValues.map(ProviderRecordValue.parseQuotedTXT)
        case "MX" where nativeValues.count == 1: [ProviderRecordValue.removingPriority(nativeValues[0])]
        default: nativeValues
        }
        let priorities = resolvedType == "MX" ? nativeValues.compactMap(ProviderRecordValue.priority) : []
        return ProviderRecordSnapshot(
            id: "\(name.lowercased())|\(resolvedType)",
            name: powerDNSRelativeName(name, zoneName: zoneName),
            type: resolvedType,
            values: displayValues,
            ttl: ttl,
            priority: Set(priorities).count == 1 ? priorities.first : nil,
            comment: comments?.compactMap(\.content).nilIfEmpty?.joined(separator: "\n"),
            metadata: [
                "disabledCount": String(records.count(where: \.disabled)),
                "valueCount": String(records.count),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct PowerDNSCreateZoneRequest: Codable, Equatable {
    let name: String
    let kind: String
    let masters: [String]
    let nameservers: [String]
}

struct PowerDNSZonePatch: Codable, Equatable {
    let rrsets: [PowerDNSRRsetChange]
}

struct PowerDNSRRsetChange: Codable, Equatable {
    let name: String
    let type: String
    let ttl: Int?
    let changetype: String
    let records: [PowerDNSRecordWrite]?
    let comments: [PowerDNSCommentWrite]?
}

struct PowerDNSRecordWrite: Codable, Equatable {
    let content: String
    let disabled: Bool
}

struct PowerDNSCommentWrite: Codable, Equatable {
    let content: String
    let account: String?
}

extension CreateProviderRecordRequest {
    func toPowerDNSChange(zoneName: String) throws -> PowerDNSRRsetChange {
        try DNSProvider.powerDNS.validateEditableRecordType(normalizedType)
        return try PowerDNSRRsetChange(
            name: powerDNSAbsoluteName(name, zoneName: zoneName),
            type: normalizedType,
            ttl: DNSProvider.powerDNS.getEffectiveTTL(ttl),
            changetype: "REPLACE",
            records: mutationValues.map {
                try PowerDNSRecordWrite(
                    content: ProviderRecordValue.writePresentation(
                        type: normalizedType,
                        value: $0,
                        priority: priority,
                        recordData: recordData,
                        provider: .powerDNS,
                        formatTXT: { ProviderRecordValue.quotedTXT($0) }
                    ),
                    disabled: false
                )
            },
            comments: comment.map { [PowerDNSCommentWrite(content: $0, account: nil)] }
        )
    }
}

extension UpdateProviderRecordRequest {
    func toPowerDNSChange(zoneName: String, existing: PowerDNSRRset) throws -> PowerDNSRRsetChange {
        let resolvedType = normalizedType(or: existing.type)
        try DNSProvider.powerDNS.validateEditableRecordType(resolvedType)
        let resolvedName = powerDNSAbsoluteName(name ?? existing.name, zoneName: zoneName)
        let existingValues = existing.records.map(\.content)
        let records: [PowerDNSRecordWrite] = if hasValueEdits || resolvedType != existing.type.uppercased() {
            try mutationValues(or: [existingValues.first ?? ""]).map {
                try PowerDNSRecordWrite(
                    content: ProviderRecordValue.writePresentation(
                        type: resolvedType,
                        value: $0,
                        priority: priority ?? ProviderRecordValue.commonPriority(existingValues),
                        recordData: recordData,
                        provider: .powerDNS,
                        formatTXT: { ProviderRecordValue.quotedTXT($0) }
                    ),
                    disabled: false
                )
            }
        } else {
            existing.records.map { PowerDNSRecordWrite(content: $0.content, disabled: $0.disabled) }
        }
        let resolvedComments = if let comment {
            [PowerDNSCommentWrite(content: comment, account: nil)]
        } else {
            existing.comments?.compactMap { value in
                value.content.map { PowerDNSCommentWrite(content: $0, account: value.account) }
            }
        }
        return PowerDNSRRsetChange(
            name: resolvedName,
            type: resolvedType,
            ttl: DNSProvider.powerDNS.getEffectiveTTL(ttl ?? existing.ttl),
            changetype: "REPLACE",
            records: records,
            comments: resolvedComments
        )
    }
}

extension PowerDNSRRsetChange {
    static func delete(name: String, type: String) -> PowerDNSRRsetChange {
        PowerDNSRRsetChange(
            name: name,
            type: type.uppercased(),
            ttl: nil,
            changetype: "DELETE",
            records: [],
            comments: []
        )
    }
}

private func powerDNSAbsoluteName(_ name: String, zoneName: String) -> String {
    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedZone = zoneName.hasSuffix(".") ? zoneName : "\(zoneName)."
    let bareZone = String(normalizedZone.dropLast())
    if value == "@" || value == bareZone || value == normalizedZone { return normalizedZone }
    if value.hasSuffix(".") { return value }
    if value.hasSuffix(".\(bareZone)") { return "\(value)." }
    return "\(value).\(normalizedZone)"
}

private func powerDNSRelativeName(_ name: String, zoneName: String) -> String {
    let bareName = name.hasSuffix(".") ? String(name.dropLast()) : name
    let bareZone = zoneName.hasSuffix(".") ? String(zoneName.dropLast()) : zoneName
    if bareName.caseInsensitiveCompare(bareZone) == .orderedSame { return "@" }
    let suffix = ".\(bareZone)"
    guard bareName.lowercased().hasSuffix(suffix.lowercased()) else { return bareName }
    return String(bareName.dropLast(suffix.count))
}

private func powerDNSNamesEqual(_ lhs: String, _ rhs: String) -> Bool {
    lhs.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        .caseInsensitiveCompare(rhs.trimmingCharacters(in: CharacterSet(charactersIn: "."))) == .orderedSame
}

private extension Array {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
