import Foundation

struct VultrDomain: Codable, Hashable {
    let domain: String
    let dateCreated: String?
    let dnsSec: String?

    enum CodingKeys: String, CodingKey {
        case domain
        case dateCreated = "date_created"
        case dnsSec = "dns_sec"
    }

    func snapshot(nameservers: [String]) -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: domain,
            name: domain,
            nameservers: nameservers,
            status: dnsSec,
            createdOn: dateCreated.flatMap(ProviderRecordValue.dateWithSQLFallback),
            metadata: dnsSec.map { ["dnssec": $0] } ?? [:],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct VultrDomainRecord: Codable, Hashable {
    let id: String
    let type: String
    let name: String
    let data: String
    let priority: Int?
    let ttl: Int?

    func snapshot(zoneName: String) -> ProviderRecordSnapshot {
        let resolvedType = type.uppercased()
        let displayData = resolvedType == "TXT" ? ProviderRecordValue.parseQuotedTXT(data) : data
        let content = resolvedType == "SRV" ? "\(priority ?? 0) \(displayData)" : displayData
        return ProviderRecordSnapshot(
            id: id,
            name: vultrDisplayName(name, zoneName: zoneName),
            type: type,
            values: [content],
            ttl: ttl,
            priority: ["MX", "SRV"].contains(type.uppercased()) ? priority : nil,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct VultrCreateDomainRequest: Codable, Equatable {
    let domain: String
}

struct VultrRecordCreateRequest: Codable, Equatable {
    let name: String
    let type: String
    let data: String
    let ttl: Int?
    let priority: Int?
}

struct VultrRecordUpdateRequest: Codable, Equatable {
    let name: String?
    let data: String?
    let ttl: Int?
    let priority: Int?
}

struct VultrDomainsEnvelope: Decodable {
    let domains: [VultrDomain]
    let meta: VultrMeta?
}

struct VultrDomainEnvelope: Decodable {
    let domain: VultrDomain
}

struct VultrRecordsEnvelope: Decodable {
    let records: [VultrDomainRecord]
    let meta: VultrMeta?
}

struct VultrRecordEnvelope: Decodable {
    let record: VultrDomainRecord
}

struct VultrMeta: Decodable {
    struct Links: Decodable {
        let next: String?
        let previous: String?

        enum CodingKeys: String, CodingKey {
            case next
            case previous = "prev"
        }
    }

    let total: Int?
    let links: Links?
}

extension CreateProviderRecordRequest {
    func toVultrRequest(zoneName: String) throws -> VultrRecordCreateRequest {
        let fields = try vultrRecordFields(
            provider: .vultr,
            type: type.uppercased(),
            content: recordData?.flatContent ?? content,
            priority: priority,
            recordData: recordData
        )
        return VultrRecordCreateRequest(
            name: ProviderDNSName.relativeEmpty(name, zoneName: zoneName),
            type: type.uppercased(),
            data: fields.data,
            ttl: DNSProvider.vultr.normalizeTTL(ttl),
            priority: fields.priority
        )
    }
}

extension UpdateProviderRecordRequest {
    func toVultrRequest(
        zoneName: String,
        existing: VultrDomainRecord
    ) throws -> VultrRecordUpdateRequest {
        if let type, type.uppercased() != existing.type.uppercased() {
            throw ProviderAPIError.invalidRecordContent(
                provider: .vultr,
                type: type,
                message: "Vultr record type changes require replacing the record"
            )
        }

        let suppliedContent = recordData?.flatContent ?? content ?? values?.first
        let fields = try suppliedContent.map {
            try vultrRecordFields(
                provider: .vultr,
                type: existing.type.uppercased(),
                content: $0,
                priority: priority ?? existing.priority,
                recordData: recordData
            )
        }

        return VultrRecordUpdateRequest(
            name: name.map { ProviderDNSName.relativeEmpty($0, zoneName: zoneName) },
            data: fields?.data,
            ttl: ttl.flatMap(DNSProvider.vultr.normalizeTTL),
            priority: fields?.priority ?? priority
        )
    }
}

private func vultrRecordFields(
    provider: DNSProvider,
    type: String,
    content: String,
    priority: Int?,
    recordData: RecordData?
) throws -> (data: String, priority: Int?) {
    let fields = try ProviderRecordValue.separatingPriority(
        provider: provider,
        type: type,
        content: content,
        priority: priority,
        recordData: recordData,
        allowsEmptySRVTarget: true,
        preservesOtherPriority: true
    )
    return (fields.content, fields.priority)
}

private func vultrDisplayName(_ name: String, zoneName: String) -> String {
    let relative = ProviderDNSName.relativeEmpty(name, zoneName: zoneName)
    return relative.isEmpty ? "@" : relative
}
