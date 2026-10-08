import Foundation

struct NameComDomain: Codable, Hashable {
    let domainName: String
    let createDate: String?
    let expireDate: String?
    let autorenewEnabled: Bool?
    let locked: Bool?
    let locks: [String]?
    let privacyEnabled: Bool?
    let nameservers: [String]?
    let renewalPrice: Double?

    func snapshot() -> ProviderZoneSnapshot {
        var metadata: [String: String] = [:]
        if let expireDate { metadata["expireDate"] = expireDate }
        if let autorenewEnabled { metadata["autorenewEnabled"] = String(autorenewEnabled) }
        if let locked { metadata["locked"] = String(locked) }
        if let privacyEnabled { metadata["privacyEnabled"] = String(privacyEnabled) }
        if let renewalPrice { metadata["renewalPrice"] = String(renewalPrice) }
        if let locks, !locks.isEmpty { metadata["locks"] = locks.joined(separator: ",") }
        return ProviderZoneSnapshot(
            id: domainName,
            name: domainName,
            nameservers: nameservers ?? [],
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct NameComDomainListResponse: Decodable {
    let domains: [NameComDomain]
    let from: Int
    let to: Int
    let totalCount: Int
    let nextPage: Int?
    let lastPage: Int?
}

struct NameComNameserverUpdateRequest: Codable, Equatable {
    let nameservers: [String]
}

struct NameComDNSRecord: Codable, Hashable {
    let answer: String
    let domainName: String
    let fqdn: String
    let host: String?
    let id: Int
    let priority: Int?
    let ttl: Int
    let type: String

    func snapshot() -> ProviderRecordSnapshot {
        let normalizedName = fqdn.hasSuffix(".") ? String(fqdn.dropLast()) : fqdn
        return ProviderRecordSnapshot(
            id: String(id),
            name: normalizedName,
            type: type,
            values: [answer],
            ttl: ttl,
            priority: (type.uppercased() == "MX" || type.uppercased() == "SRV") ? priority : nil,
            aliasTarget: type.uppercased() == "ANAME"
                ? DNSAliasTarget(name: answer, zoneId: nil, evaluateTargetHealth: nil)
                : nil,
            metadata: ["host": host ?? ""],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct NameComRecordListResponse: Decodable {
    let records: [NameComDNSRecord]
    let from: Int
    let to: Int
    let totalCount: Int
    let nextPage: Int?
    let lastPage: Int?
}

struct NameComRecordWriteRequest: Codable, Equatable {
    let type: String
    let host: String
    let answer: String
    let ttl: Int
    let priority: Int?
}

extension CreateProviderRecordRequest {
    func toNameComRequests(zoneName: String) throws -> [NameComRecordWriteRequest] {
        let type = type.uppercased()
        try validateNameComRecordType(type)
        let values = values ?? [recordData?.flatContent ?? content]
        return try values.map {
            try NameComRecordWriteRequest(
                type: type,
                host: ProviderDNSName.relativeEmptyCaseInsensitive(name, zoneName: zoneName),
                content: $0,
                ttl: DNSProvider.nameCom.getEffectiveTTL(ttl) ?? DNSProvider.nameCom.defaultTTL,
                priority: priority,
                recordData: recordData
            )
        }
    }
}

extension UpdateProviderRecordRequest {
    func toNameComRequest(zoneName: String, existing: NameComDNSRecord) throws -> NameComRecordWriteRequest {
        guard values == nil || values?.count == 1 else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .nameCom,
                type: type ?? existing.type,
                message: "individual Name.com record edits accept exactly one value"
            )
        }
        let type = (type ?? existing.type).uppercased()
        try validateNameComRecordType(type)
        return try NameComRecordWriteRequest(
            type: type,
            host: ProviderDNSName.relativeEmptyCaseInsensitive(name ?? existing.host ?? "", zoneName: zoneName),
            content: values?.first ?? recordData?.flatContent ?? content ?? existing.answer,
            ttl: DNSProvider.nameCom.normalizeTTL(ttl ?? existing.ttl) ?? DNSProvider.nameCom.defaultTTL,
            priority: priority ?? existing.priority,
            recordData: recordData
        )
    }
}

private extension NameComRecordWriteRequest {
    init(
        type: String,
        host: String,
        content: String,
        ttl: Int,
        priority: Int?,
        recordData: RecordData?
    ) throws {
        let fields = try ProviderRecordValue.separatingPriority(
            provider: .nameCom,
            type: type,
            content: content,
            priority: priority,
            recordData: recordData,
            acceptsUnprefixedSRV: true,
            validatesSRVRange: true
        )
        self.init(type: type, host: host, answer: fields.content, ttl: ttl, priority: fields.priority)
    }
}

private func validateNameComRecordType(_ type: String) throws {
    guard DNSProvider.nameCom.capabilities.canEdit(recordType: type) else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .nameCom,
            type: type,
            message: "the record type is unsupported by Name.com Core API"
        )
    }
}
