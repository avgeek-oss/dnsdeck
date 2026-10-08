import Foundation

struct DeSECDomain: Codable, Hashable {
    let name: String
    let minimumTTL: Int
    let created: String?
    let published: String?
    let touched: String?

    enum CodingKeys: String, CodingKey {
        case name
        case minimumTTL = "minimum_ttl"
        case created, published, touched
    }

    func snapshot() -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: name,
            name: name,
            nameservers: ["ns1.desec.io", "ns2.desec.org"],
            createdOn: created.flatMap(ProviderRecordValue.date),
            metadata: ["minimumTTL": String(minimumTTL)],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct DeSECRRset: Codable, Hashable {
    let created: String?
    let domain: String?
    let subname: String
    let name: String?
    let type: String
    let records: [String]
    let ttl: Int
    let touched: String?

    func snapshot() -> ProviderRecordSnapshot {
        let resolvedType = type.uppercased()
        let displayValues: [String] = switch resolvedType {
        case "TXT": records.map(ProviderRecordValue.parseQuotedTXT)
        case "MX" where records.count == 1: [ProviderRecordValue.removingPriority(records[0])]
        default: records
        }
        let priorities = resolvedType == "MX" ? records.compactMap(ProviderRecordValue.priority) : []
        let isProtected = (subname.isEmpty && resolvedType == "NS") || deSECManagedTypes.contains(resolvedType)

        return ProviderRecordSnapshot(
            id: "\(subname)|\(resolvedType)",
            name: subname.isEmpty ? "@" : subname,
            type: resolvedType,
            values: displayValues,
            ttl: ttl,
            priority: Set(priorities).count == 1 ? priorities.first : nil,
            createdOn: created.flatMap(ProviderRecordValue.date),
            modifiedOn: touched.flatMap(ProviderRecordValue.date),
            metadata: [
                "isProtected": String(isProtected),
                "valueCount": String(records.count),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct DeSECCreateDomainRequest: Codable, Equatable {
    let name: String
}

struct DeSECRRsetWriteRequest: Codable, Equatable {
    let subname: String
    let type: String
    let ttl: Int
    let records: [String]
}

struct DeSECRRsetMutation {
    let request: DeSECRRsetWriteRequest
}

extension CreateProviderRecordRequest {
    func toDeSECMutation(zoneName: String, minimumTTL: Int) throws -> DeSECRRsetMutation {
        try DNSProvider.deSEC.validateEditableRecordType(normalizedType)
        return try DeSECRRsetMutation(
            request: DeSECRRsetWriteRequest(
                subname: ProviderDNSName.relativeEmpty(name, zoneName: zoneName),
                type: normalizedType,
                ttl: deSECTTL(ttl, minimum: minimumTTL),
                records: mutationValues.map {
                    let presentation = try ProviderRecordValue.writePresentation(
                        type: normalizedType,
                        value: $0,
                        priority: priority,
                        recordData: recordData,
                        provider: .deSEC,
                        formatTXT: { ProviderRecordValue.quotedTXT($0) }
                    )
                    return deSECAbsoluteTargets(in: presentation, type: normalizedType)
                }
            )
        )
    }
}

extension UpdateProviderRecordRequest {
    func toDeSECMutation(
        zoneName: String,
        minimumTTL: Int,
        existing: DeSECRRset
    ) throws -> DeSECRRsetMutation {
        let resolvedType = normalizedType(or: existing.type)
        try DNSProvider.deSEC.validateEditableRecordType(resolvedType)

        return try DeSECRRsetMutation(
            request: DeSECRRsetWriteRequest(
                subname: ProviderDNSName.relativeEmpty(name ?? existing.subname, zoneName: zoneName),
                type: resolvedType,
                ttl: deSECTTL(ttl ?? existing.ttl, minimum: minimumTTL),
                records: mutationValues(or: existing.records).map {
                    let presentation = try ProviderRecordValue.writePresentation(
                        type: resolvedType,
                        value: $0,
                        priority: priority ?? ProviderRecordValue.commonPriority(existing.records),
                        recordData: recordData,
                        provider: .deSEC,
                        preserveNativeValue: !hasValueEdits && resolvedType == existing.type,
                        formatTXT: { ProviderRecordValue.quotedTXT($0) }
                    )
                    return deSECAbsoluteTargets(in: presentation, type: resolvedType)
                }
            )
        )
    }
}

private let deSECManagedTypes: Set = ["CDNSKEY", "CDS", "DNSKEY", "DS", "NSEC3PARAM", "RRSIG", "SOA"]

private func deSECTTL(_ ttl: Int?, minimum: Int) -> Int {
    max(minimum, min(86400, ttl ?? DNSProvider.deSEC.defaultTTL))
}

private func deSECAbsoluteTargets(in presentation: String, type: String) -> String {
    switch type {
    case "CNAME", "NS":
        return deSECAbsoluteTarget(presentation)
    case "MX", "SRV":
        var fields = presentation.split(whereSeparator: \Character.isWhitespace).map(String.init)
        guard fields.count >= 2 else { return presentation }
        fields[fields.count - 1] = deSECAbsoluteTarget(fields[fields.count - 1])
        return fields.joined(separator: " ")
    default:
        return presentation
    }
}

private func deSECAbsoluteTarget(_ value: String) -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value != ".", !value.hasSuffix(".") else { return value }
    return "\(value)."
}
