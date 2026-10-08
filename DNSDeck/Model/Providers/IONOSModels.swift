import Foundation

struct IONOSZone: Codable, Hashable {
    let id: String
    let name: String
    let type: String

    func snapshot(nameservers: [String] = []) -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: id,
            name: name,
            nameservers: nameservers,
            status: type,
            metadata: ["type": type],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct IONOSCustomerZone: Codable, Hashable {
    let id: String
    let name: String
    let type: String
    let records: [IONOSRecord]

    var nameservers: [String] {
        records
            .filter {
                $0.type.uppercased() == "NS" &&
                    $0.disabled != true &&
                    $0.name.caseInsensitiveCompare(name) == .orderedSame
            }
            .map(\.content)
    }

    func snapshot() -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: id,
            name: name,
            nameservers: nameservers,
            status: type,
            metadata: ["type": type],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct IONOSRecord: Codable, Hashable {
    let id: String
    let name: String
    let rootName: String?
    let type: String
    let content: String
    let changeDate: String?
    let ttl: Int?
    let prio: Int?
    let disabled: Bool?

    func snapshot() -> ProviderRecordSnapshot {
        let type = type.uppercased()
        var metadata: [String: String] = [:]
        if let rootName { metadata["rootName"] = rootName }
        if let disabled { metadata["disabled"] = String(disabled) }
        return ProviderRecordSnapshot(
            id: id,
            name: name,
            type: type,
            values: [type == "TXT" ? ProviderRecordValue.parseQuotedTXT(content) : content],
            ttl: ttl,
            priority: (type == "MX" || type == "SRV") ? prio : nil,
            modifiedOn: changeDate.flatMap(DateFormatter.iso8601.date),
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct IONOSRecordCreateRequest: Codable, Equatable {
    let name: String
    let type: String
    let content: String
    let ttl: Int
    let prio: Int?
    let disabled: Bool
}

struct IONOSRecordUpdateRequest: Codable, Equatable {
    let content: String
    let ttl: Int
    let prio: Int?
    let disabled: Bool
}

struct IONOSRecordMutation {
    let name: String
    let type: String
    let content: String
    let ttl: Int
    let priority: Int?
    let disabled: Bool

    var createRequest: IONOSRecordCreateRequest {
        IONOSRecordCreateRequest(
            name: name,
            type: type,
            content: content,
            ttl: ttl,
            prio: priority,
            disabled: disabled
        )
    }

    var updateRequest: IONOSRecordUpdateRequest {
        IONOSRecordUpdateRequest(content: content, ttl: ttl, prio: priority, disabled: disabled)
    }
}

extension CreateProviderRecordRequest {
    func toIONOSMutations(zoneName: String) throws -> [IONOSRecordMutation] {
        let type = type.uppercased()
        try validateIONOSRecordType(type)
        let values = values ?? [recordData?.flatContent ?? content]
        return try values.map {
            try IONOSRecordMutation(
                name: ionosAbsoluteName(name, zoneName: zoneName),
                type: type,
                content: $0,
                ttl: DNSProvider.ionos.getEffectiveTTL(ttl) ?? DNSProvider.ionos.defaultTTL,
                priority: priority,
                disabled: false,
                recordData: recordData
            )
        }
    }
}

extension UpdateProviderRecordRequest {
    func toIONOSMutation(zoneName: String, existing: IONOSRecord) throws -> IONOSRecordMutation {
        guard values == nil || values?.count == 1 else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ionos,
                type: type ?? existing.type,
                message: "individual IONOS record edits accept exactly one value"
            )
        }
        let type = (type ?? existing.type).uppercased()
        try validateIONOSRecordType(type)
        return try IONOSRecordMutation(
            name: ionosAbsoluteName(name ?? existing.name, zoneName: zoneName),
            type: type,
            content: values?.first ?? recordData?.flatContent ?? content ?? existing.snapshot().content,
            ttl: DNSProvider.ionos.normalizeTTL(ttl ?? existing.ttl) ?? DNSProvider.ionos.defaultTTL,
            priority: priority ?? existing.prio,
            disabled: existing.disabled ?? false,
            recordData: recordData
        )
    }
}

private extension IONOSRecordMutation {
    init(
        name: String,
        type: String,
        content: String,
        ttl: Int,
        priority: Int?,
        disabled: Bool,
        recordData: RecordData?
    ) throws {
        let fields = try ProviderRecordValue.separatingPriority(
            provider: .ionos,
            type: type,
            content: type == "TXT" ? ProviderRecordValue.parseQuotedTXT(content) : content,
            priority: priority,
            recordData: recordData,
            acceptsUnprefixedSRV: true,
            validatesSRVRange: true
        )

        self.init(
            name: name,
            type: type,
            content: fields.content,
            ttl: ttl,
            priority: fields.priority,
            disabled: disabled
        )
    }
}

private func validateIONOSRecordType(_ type: String) throws {
    guard DNSProvider.ionos.capabilities.canEdit(recordType: type) else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .ionos,
            type: type,
            message: "the record type is provider-managed or unsupported by IONOS Hosting DNS"
        )
    }
}

private func ionosAbsoluteName(_ name: String, zoneName: String) -> String {
    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let zone = zoneName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    if value.isEmpty || value == "@" || value.caseInsensitiveCompare(zone) == .orderedSame { return zone }
    let suffix = ".\(zone)"
    return value.lowercased().hasSuffix(suffix.lowercased()) ? value : "\(value).\(zone)"
}
