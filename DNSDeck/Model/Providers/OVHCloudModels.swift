import Foundation

struct OVHCloudZone: Codable, Hashable {
    let dnssecSupported: Bool
    let hasDnsAnycast: Bool
    let name: String
    let nameServers: [String]

    func snapshot() -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: name,
            name: name,
            nameservers: nameServers,
            metadata: [
                "dnssecSupported": String(dnssecSupported),
                "hasDnsAnycast": String(hasDnsAnycast),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct OVHCloudNameserver: Codable, Equatable {
    let host: String
}

struct OVHCloudNameserverUpdateRequest: Codable, Equatable {
    let nameServer: [OVHCloudNameserver]
}

struct OVHCloudRecord: Codable, Hashable {
    let id: Int64
    let zone: String
    let target: String
    let ttl: Int?
    let fieldType: String
    let subDomain: String?

    func snapshot() -> ProviderRecordSnapshot {
        let type = fieldType.uppercased()
        let displayValue: String = switch type {
        case "TXT": ovhCloudParseTXT(target)
        case "MX": ProviderRecordValue.removingPriority(target)
        default: target
        }
        return ProviderRecordSnapshot(
            id: String(id),
            name: subDomain?.nilIfEmpty ?? "@",
            type: type,
            values: [displayValue],
            ttl: ttl == 0 ? Constants.TTL.automatic : ttl,
            priority: type == "MX" ? ProviderRecordValue.priority(target) : nil,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct OVHCloudRecordCreate: Codable, Equatable {
    let fieldType: String
    let subDomain: String?
    let target: String
    let ttl: Int
}

struct OVHCloudRecordUpdate: Codable, Equatable {
    let subDomain: String?
    let target: String
    let ttl: Int?
}

extension CreateProviderRecordRequest {
    func toOVHCloudCreate(zoneName: String) throws -> OVHCloudRecordCreate {
        let resolvedType = type.uppercased()
        try validateOVHCloudType(resolvedType)
        return try OVHCloudRecordCreate(
            fieldType: resolvedType,
            subDomain: ProviderDNSName.relativeEmpty(name, zoneName: zoneName).nilIfEmpty,
            target: ovhCloudWriteTarget(
                type: resolvedType,
                content: recordData?.flatContent ?? content,
                priority: recordData?.priority ?? priority
            ),
            ttl: DNSProvider.ovhCloud.getEffectiveTTL(ttl) ?? DNSProvider.ovhCloud.defaultTTL
        )
    }
}

extension UpdateProviderRecordRequest {
    func toOVHCloudUpdate(zoneName: String, existing: OVHCloudRecord) throws -> OVHCloudRecordUpdate {
        let resolvedType = (type ?? existing.fieldType).uppercased()
        guard resolvedType == existing.fieldType.uppercased() else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ovhCloud,
                type: resolvedType,
                message: "record type changes require create-and-delete"
            )
        }
        return try OVHCloudRecordUpdate(
            subDomain: ProviderDNSName.relativeEmpty(name ?? existing.subDomain ?? "", zoneName: zoneName).nilIfEmpty,
            target: ovhCloudWriteTarget(
                type: resolvedType,
                content: recordData?.flatContent ?? content ?? existing.target,
                priority: recordData?.priority ?? priority ?? ProviderRecordValue.priority(existing.target),
                preserveNative: recordData == nil && content == nil && priority == nil
            ),
            ttl: DNSProvider.ovhCloud.getEffectiveTTL(ttl ?? existing.ttl)
        )
    }

    func toOVHCloudCreate(zoneName: String, existing: OVHCloudRecord) throws -> OVHCloudRecordCreate {
        let resolvedType = (type ?? existing.fieldType).uppercased()
        try validateOVHCloudType(resolvedType)
        let sourceContent = recordData?.flatContent ?? content ?? existing.snapshot().content
        return try OVHCloudRecordCreate(
            fieldType: resolvedType,
            subDomain: ProviderDNSName.relativeEmpty(name ?? existing.subDomain ?? "", zoneName: zoneName).nilIfEmpty,
            target: ovhCloudWriteTarget(
                type: resolvedType,
                content: sourceContent,
                priority: recordData?.priority ?? priority ?? existing.snapshot().priority
            ),
            ttl: DNSProvider.ovhCloud.getEffectiveTTL(ttl ?? existing.ttl) ?? DNSProvider.ovhCloud.defaultTTL
        )
    }
}

private func validateOVHCloudType(_ type: String) throws {
    guard DNSProvider.ovhCloud.capabilities.canEdit(recordType: type) else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .ovhCloud,
            type: type,
            message: "the record type is unsupported"
        )
    }
}

private func ovhCloudWriteTarget(
    type: String,
    content: String,
    priority: Int?,
    preserveNative: Bool = false
) throws -> String {
    if preserveNative { return content }
    switch type {
    case "MX":
        let parts = content.split(whereSeparator: \Character.isWhitespace)
        if parts.first.flatMap({ Int($0) }) != nil { return content }
        return "\(priority ?? 10) \(content)"
    case "SRV":
        let parts = content.split(whereSeparator: \Character.isWhitespace)
        guard parts.count >= 4, parts.prefix(3).allSatisfy({ Int($0) != nil }) else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .ovhCloud,
                type: type,
                message: "expected priority, weight, port, and target"
            )
        }
        return content
    case "TXT":
        return ovhCloudParseTXT(content)
    default:
        return content
    }
}

private func ovhCloudParseTXT(_ value: String) -> String {
    guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return value }
    return String(value.dropFirst().dropLast())
        .replacingOccurrences(of: "\\\"", with: "\"")
        .replacingOccurrences(of: "\\\\", with: "\\")
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
