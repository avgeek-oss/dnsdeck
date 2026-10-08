import Foundation

struct DNSimpleZone: Codable, Hashable {
    let id: Int
    let accountId: Int
    let name: String
    let reverse: Bool
    let secondary: Bool
    let lastTransferredAt: String?
    let active: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case name
        case reverse
        case secondary
        case lastTransferredAt = "last_transferred_at"
        case active
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func snapshot(nameservers: [String]) -> ProviderZoneSnapshot {
        var metadata = [
            "active": String(active),
            "reverse": String(reverse),
            "secondary": String(secondary),
        ]
        if let lastTransferredAt { metadata["lastTransferredAt"] = lastTransferredAt }
        metadata["updatedAt"] = updatedAt
        return ProviderZoneSnapshot(
            id: String(id),
            name: name,
            nameservers: secondary ? [] : nameservers,
            status: active ? "active" : "inactive",
            createdOn: ProviderRecordValue.date(createdAt),
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct DNSimpleZoneRecord: Codable, Hashable {
    let id: Int
    let zoneId: String
    let parentId: Int?
    let name: String
    let content: String
    let ttl: Int
    let priority: Int?
    let type: String
    let regions: [String]
    let systemRecord: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case zoneId = "zone_id"
        case parentId = "parent_id"
        case name
        case content
        case ttl
        case priority
        case type
        case regions
        case systemRecord = "system_record"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func snapshot() -> ProviderRecordSnapshot {
        let normalizedType = type.uppercased()
        let displayContent = normalizedType == "TXT"
            ? ProviderRecordValue.parseQuotedTXT(content, allowEmpty: true)
            : content
        var metadata = [
            "regions": regions.joined(separator: ","),
            "systemRecord": String(systemRecord),
        ]
        if let parentId { metadata["parentId"] = String(parentId) }
        return ProviderRecordSnapshot(
            id: String(id),
            name: name.isEmpty ? "@" : name,
            type: type,
            values: [normalizedType == "SRV" ? "\(priority ?? 0) \(displayContent)" : displayContent],
            ttl: ttl,
            priority: ["MX", "SRV"].contains(normalizedType) ? priority : nil,
            createdOn: ProviderRecordValue.date(createdAt),
            modifiedOn: ProviderRecordValue.date(updatedAt),
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct DNSimplePagination: Decodable {
    let currentPage: Int
    let perPage: Int
    let totalEntries: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case perPage = "per_page"
        case totalEntries = "total_entries"
        case totalPages = "total_pages"
    }
}

struct DNSimpleCollectionEnvelope<Item: Decodable>: Decodable {
    let data: [Item]
    let pagination: DNSimplePagination
}

struct DNSimpleSingleEnvelope<Item: Decodable>: Decodable {
    let data: Item
}

struct DNSimpleRecordCreateRequest: Codable, Equatable {
    let name: String
    let type: String
    let content: String
    let ttl: Int?
    let priority: Int?
    let integratedZones: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case content
        case ttl
        case priority
        case integratedZones = "integrated_zones"
    }
}

struct DNSimpleRecordUpdateRequest: Codable, Equatable {
    let name: String?
    let content: String?
    let ttl: Int?
    let priority: Int?
    let integratedZones: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case content
        case ttl
        case priority
        case integratedZones = "integrated_zones"
    }
}

extension CreateProviderRecordRequest {
    func toDNSimpleRequest(zoneName: String) throws -> DNSimpleRecordCreateRequest {
        let fields = try dnsimpleRecordFields(
            type: type.uppercased(),
            content: recordData?.flatContent ?? content,
            priority: priority,
            recordData: recordData
        )
        return DNSimpleRecordCreateRequest(
            name: ProviderDNSName.relativeEmpty(name, zoneName: zoneName),
            type: type.uppercased(),
            content: fields.content,
            ttl: DNSProvider.dnsimple.normalizeTTL(ttl),
            priority: fields.priority,
            integratedZones: ["dnsimple"]
        )
    }
}

extension UpdateProviderRecordRequest {
    func toDNSimpleRequest(
        zoneName: String,
        existing: DNSimpleZoneRecord
    ) throws -> DNSimpleRecordUpdateRequest {
        if let type, type.uppercased() != existing.type.uppercased() {
            throw ProviderAPIError.invalidRecordContent(
                provider: .dnsimple,
                type: type,
                message: "DNSimple record type changes require replacing the record"
            )
        }

        let suppliedContent = recordData?.flatContent ?? content ?? values?.first
        let fields = try suppliedContent.map {
            try dnsimpleRecordFields(
                type: existing.type.uppercased(),
                content: $0,
                priority: priority ?? existing.priority,
                recordData: recordData
            )
        }
        let allowsPriority = ["MX", "SRV"].contains(existing.type.uppercased())
        return DNSimpleRecordUpdateRequest(
            name: name.map { ProviderDNSName.relativeEmpty($0, zoneName: zoneName) },
            content: fields?.content,
            ttl: ttl.flatMap(DNSProvider.dnsimple.normalizeTTL),
            priority: allowsPriority ? fields?.priority ?? priority : nil,
            integratedZones: ["dnsimple"]
        )
    }
}

private func dnsimpleRecordFields(
    type: String,
    content: String,
    priority: Int?,
    recordData: RecordData?
) throws -> (content: String, priority: Int?) {
    let fields = try ProviderRecordValue.separatingPriority(
        provider: .dnsimple,
        type: type,
        content: content,
        priority: priority,
        recordData: recordData,
        allowsEmptySRVTarget: true
    )
    return (fields.content, fields.priority)
}
