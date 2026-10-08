import Foundation

struct GandiDomain: Codable, Hashable {
    let fqdn: String
    let domainHref: String?
    let domainKeysHref: String?
    let domainRecordsHref: String?
    let automaticSnapshots: Bool?

    enum CodingKeys: String, CodingKey {
        case fqdn
        case domainHref = "domain_href"
        case domainKeysHref = "domain_keys_href"
        case domainRecordsHref = "domain_records_href"
        case automaticSnapshots = "automatic_snapshots"
    }

    func snapshot(nameservers: [String] = []) -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: fqdn,
            name: fqdn,
            nameservers: nameservers,
            metadata: automaticSnapshots.map { ["automaticSnapshots": String($0)] } ?? [:],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct GandiRecordSet: Codable, Hashable {
    let rrsetName: String
    let rrsetType: String
    let rrsetValues: [String]
    let rrsetTTL: Int?
    let rrsetHref: String?

    enum CodingKeys: String, CodingKey {
        case rrsetName = "rrset_name"
        case rrsetType = "rrset_type"
        case rrsetValues = "rrset_values"
        case rrsetTTL = "rrset_ttl"
        case rrsetHref = "rrset_href"
    }

    func snapshot() -> ProviderRecordSnapshot {
        let displayValues: [String] = switch rrsetType.uppercased() {
        case "TXT": rrsetValues.map(ProviderRecordValue.parseQuotedTXT)
        case "MX" where rrsetValues.count == 1: [ProviderRecordValue.removingPriority(rrsetValues[0])]
        default: rrsetValues
        }
        let priorities = rrsetType.uppercased() == "MX"
            ? rrsetValues.compactMap(ProviderRecordValue.priority)
            : []
        return ProviderRecordSnapshot(
            id: "\(rrsetName)|\(rrsetType.uppercased())",
            name: rrsetName,
            type: rrsetType,
            values: displayValues,
            ttl: rrsetTTL,
            priority: Set(priorities).count == 1 ? priorities.first : nil,
            metadata: ["valueCount": String(rrsetValues.count)],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct GandiCreateDomainRequest: Codable, Equatable {
    let fqdn: String
}

struct GandiRecordSetWriteRequest: Codable, Equatable {
    let rrsetValues: [String]
    let rrsetTTL: Int?

    enum CodingKeys: String, CodingKey {
        case rrsetValues = "rrset_values"
        case rrsetTTL = "rrset_ttl"
    }
}

struct GandiRecordMutation {
    let name: String
    let type: String
    let request: GandiRecordSetWriteRequest
}

extension CreateProviderRecordRequest {
    func toGandiMutation(zoneName: String) throws -> GandiRecordMutation {
        try DNSProvider.gandi.validateEditableRecordType(normalizedType)
        return try GandiRecordMutation(
            name: ProviderDNSName.relativeAt(name, zoneName: zoneName),
            type: normalizedType,
            request: GandiRecordSetWriteRequest(
                rrsetValues: mutationValues.map {
                    try ProviderRecordValue.writePresentation(
                        type: normalizedType,
                        value: $0,
                        priority: priority,
                        recordData: recordData,
                        provider: .gandi,
                        formatTXT: { ProviderRecordValue.quotedTXT($0, maximumChunkBytes: 255) }
                    )
                },
                rrsetTTL: DNSProvider.gandi.normalizeTTL(ttl)
            )
        )
    }
}

extension UpdateProviderRecordRequest {
    func toGandiMutation(
        zoneName: String,
        existing: GandiRecordSet
    ) throws -> GandiRecordMutation {
        let resolvedType = normalizedType(or: existing.rrsetType)
        try DNSProvider.gandi.validateEditableRecordType(resolvedType)
        return try GandiRecordMutation(
            name: ProviderDNSName.relativeAt(name ?? existing.rrsetName, zoneName: zoneName),
            type: resolvedType,
            request: GandiRecordSetWriteRequest(
                rrsetValues: mutationValues(or: existing.rrsetValues).map {
                    try ProviderRecordValue.writePresentation(
                        type: resolvedType,
                        value: $0,
                        priority: priority ?? ProviderRecordValue.commonPriority(existing.rrsetValues),
                        recordData: recordData,
                        provider: .gandi,
                        preserveNativeValue: !hasValueEdits,
                        formatTXT: { ProviderRecordValue.quotedTXT($0, maximumChunkBytes: 255) }
                    )
                },
                rrsetTTL: DNSProvider.gandi.normalizeTTL(ttl ?? existing.rrsetTTL)
            )
        )
    }
}
