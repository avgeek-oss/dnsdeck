import Foundation

struct ScalewayDNSZone: Codable, Hashable {
    let domain: String
    let subdomain: String
    let ns: [String]
    let nsDefault: [String]
    let nsMaster: [String]
    let status: String
    let message: String?
    let updatedAt: String?
    let projectId: String
    let linkedProducts: [String]?

    enum CodingKeys: String, CodingKey {
        case domain, subdomain, ns, status, message
        case nsDefault = "ns_default"
        case nsMaster = "ns_master"
        case updatedAt = "updated_at"
        case projectId = "project_id"
        case linkedProducts = "linked_products"
    }

    var name: String {
        subdomain.isEmpty ? domain : "\(subdomain).\(domain)"
    }

    var isWritable: Bool {
        status.lowercased() == "active" && nsMaster.isEmpty
    }

    func snapshot() -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: name,
            name: name,
            nameservers: ns,
            status: status,
            metadata: [
                "domain": domain,
                "projectId": projectId,
                "isWritable": String(isWritable),
            ],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct ScalewayNameserver: Codable, Equatable {
    let name: String
    let ip: [String]
}

struct ScalewayNameserverUpdateRequest: Codable, Equatable {
    let nameservers: [ScalewayNameserver]

    enum CodingKeys: String, CodingKey {
        case nameservers = "ns"
    }
}

struct ScalewayRecord: Codable, Hashable {
    let data: String
    let name: String
    let priority: Int
    let ttl: Int
    let type: String
    let comment: String?
    let geoIPConfig: [String: ProviderJSONValue]?
    let httpServiceConfig: [String: ProviderJSONValue]?
    let weightedConfig: [String: ProviderJSONValue]?
    let viewConfig: [String: ProviderJSONValue]?
    let id: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case data, name, priority, ttl, type, comment, id
        case geoIPConfig = "geo_ip_config"
        case httpServiceConfig = "http_service_config"
        case weightedConfig = "weighted_config"
        case viewConfig = "view_config"
        case updatedAt = "updated_at"
    }

    func snapshot() -> ProviderRecordSnapshot {
        let resolvedType = type.uppercased()
        let displayData = resolvedType == "TXT" ? scalewayParseTXT(data) : data
        let hasRouting = geoIPConfig != nil || httpServiceConfig != nil || weightedConfig != nil || viewConfig != nil
        return ProviderRecordSnapshot(
            id: id,
            name: name.isEmpty ? "@" : name,
            type: resolvedType,
            values: [displayData],
            ttl: ttl,
            priority: ["MX", "SRV"].contains(resolvedType) ? priority : nil,
            comment: comment,
            routingPolicy: hasRouting
                ? DNSRecordRoutingPolicy(
                    identifier: id,
                    weight: nil,
                    region: nil,
                    continent: nil,
                    country: nil,
                    subdivision: nil,
                    failover: nil,
                    multiValueAnswer: nil,
                    healthCheckId: nil
                )
                : nil,
            metadata: ["hasAdvancedConfiguration": String(hasRouting)],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct ScalewayListZonesResponse: Decodable {
    let totalCount: Int
    let dnsZones: [ScalewayDNSZone]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case dnsZones = "dns_zones"
    }
}

struct ScalewayListRecordsResponse: Decodable {
    let totalCount: Int
    let records: [ScalewayRecord]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case records
    }
}

struct ScalewayRecordWrite: Codable, Equatable {
    let data: String
    let name: String
    let priority: Int
    let ttl: Int
    let type: String
    let comment: String?
    let geoIPConfig: [String: ProviderJSONValue]?
    let httpServiceConfig: [String: ProviderJSONValue]?
    let weightedConfig: [String: ProviderJSONValue]?
    let viewConfig: [String: ProviderJSONValue]?

    enum CodingKeys: String, CodingKey {
        case data, name, priority, ttl, type, comment
        case geoIPConfig = "geo_ip_config"
        case httpServiceConfig = "http_service_config"
        case weightedConfig = "weighted_config"
        case viewConfig = "view_config"
    }
}

struct ScalewayRecordChange: Codable, Equatable {
    struct Add: Codable, Equatable { let records: [ScalewayRecordWrite] }
    struct Set: Codable, Equatable {
        let id: String
        let records: [ScalewayRecordWrite]
    }

    struct Delete: Codable, Equatable { let id: String }

    let add: Add?
    let set: Set?
    let delete: Delete?

    static func add(_ record: ScalewayRecordWrite) -> ScalewayRecordChange {
        ScalewayRecordChange(add: Add(records: [record]), set: nil, delete: nil)
    }

    static func set(id: String, record: ScalewayRecordWrite) -> ScalewayRecordChange {
        ScalewayRecordChange(add: nil, set: Set(id: id, records: [record]), delete: nil)
    }

    static func delete(id: String) -> ScalewayRecordChange {
        ScalewayRecordChange(add: nil, set: nil, delete: Delete(id: id))
    }
}

struct ScalewayUpdateRecordsRequest: Codable, Equatable {
    let changes: [ScalewayRecordChange]
    let returnAllRecords: Bool
    let disallowNewZoneCreation: Bool

    enum CodingKeys: String, CodingKey {
        case changes
        case returnAllRecords = "return_all_records"
        case disallowNewZoneCreation = "disallow_new_zone_creation"
    }
}

extension CreateProviderRecordRequest {
    func toScalewayRecord(zoneName: String) throws -> ScalewayRecordWrite {
        let resolvedType = type.uppercased()
        try validateScalewayType(resolvedType)
        let rawContent = recordData?.flatContent ?? content
        return ScalewayRecordWrite(
            data: scalewayWriteData(type: resolvedType, content: rawContent),
            name: ProviderDNSName.relativeEmpty(name, zoneName: zoneName),
            priority: ["MX", "SRV"].contains(resolvedType)
                ? (recordData?.priority ?? priority ?? scalewayEmbeddedPriority(
                    type: resolvedType,
                    content: rawContent
                ) ?? 0)
                : 0,
            ttl: DNSProvider.scaleway.getEffectiveTTL(ttl) ?? DNSProvider.scaleway.defaultTTL,
            type: resolvedType,
            comment: comment,
            geoIPConfig: nil,
            httpServiceConfig: nil,
            weightedConfig: nil,
            viewConfig: nil
        )
    }
}

extension UpdateProviderRecordRequest {
    func toScalewayRecord(zoneName: String, existing: ScalewayRecord) throws -> ScalewayRecordWrite {
        let resolvedType = (type ?? existing.type).uppercased()
        try validateScalewayType(resolvedType)
        let keepsConfiguration = resolvedType == existing.type.uppercased()
        if !keepsConfiguration, recordData == nil, content == nil {
            throw ProviderAPIError.invalidRecordContent(
                provider: .scaleway,
                type: resolvedType,
                message: "record type changes require replacement content"
            )
        }
        let rawContent = recordData?.flatContent ?? content ?? existing.data
        return ScalewayRecordWrite(
            data: scalewayWriteData(type: resolvedType, content: rawContent),
            name: ProviderDNSName.relativeEmpty(name ?? existing.name, zoneName: zoneName),
            priority: ["MX", "SRV"].contains(resolvedType)
                ? (recordData?.priority ?? priority ?? scalewayEmbeddedPriority(
                    type: resolvedType,
                    content: rawContent
                ) ?? existing.priority)
                : 0,
            ttl: DNSProvider.scaleway.getEffectiveTTL(ttl ?? existing.ttl) ?? existing.ttl,
            type: resolvedType,
            comment: comment ?? existing.comment,
            geoIPConfig: keepsConfiguration ? existing.geoIPConfig : nil,
            httpServiceConfig: keepsConfiguration ? existing.httpServiceConfig : nil,
            weightedConfig: keepsConfiguration ? existing.weightedConfig : nil,
            viewConfig: keepsConfiguration ? existing.viewConfig : nil
        )
    }
}

private func validateScalewayType(_ type: String) throws {
    guard DNSProvider.scaleway.capabilities.canEdit(recordType: type) else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .scaleway,
            type: type,
            message: "the record type is unsupported"
        )
    }
}

private func scalewayWriteData(type: String, content: String) -> String {
    if type == "SRV" {
        let fields = content.split(whereSeparator: \Character.isWhitespace)
        if fields.count >= 4, fields.prefix(3).allSatisfy({ Int($0) != nil }) {
            return fields.dropFirst().joined(separator: " ")
        }
    }
    guard type == "TXT", content.hasPrefix("\""), content.hasSuffix("\"") else { return content }
    return scalewayParseTXT(content)
}

private func scalewayEmbeddedPriority(type: String, content: String) -> Int? {
    guard type == "SRV" else { return nil }
    let fields = content.split(whereSeparator: \Character.isWhitespace)
    guard fields.count >= 4 else { return nil }
    return Int(fields[0])
}

private func scalewayParseTXT(_ value: String) -> String {
    guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return value }
    return String(value.dropFirst().dropLast())
        .replacingOccurrences(of: "\\\"", with: "\"")
        .replacingOccurrences(of: "\\\\", with: "\\")
}
