import Foundation

struct GoDaddyDomain: Codable, Hashable {
    let domain: String
    let domainId: Double?
    let status: String?
    let nameServers: [String]?
    let createdAt: String?

    func snapshot() -> ProviderZoneSnapshot {
        var metadata: [String: String] = [:]
        if let domainId { metadata["domainId"] = String(domainId) }
        return ProviderZoneSnapshot(
            id: domain,
            name: domain,
            nameservers: nameServers ?? [],
            status: status,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct GoDaddyNameserverUpdateRequest: Codable, Equatable {
    let nameServers: [String]
}

struct GoDaddyDNSRecord: Codable, Hashable {
    let type: String
    let name: String
    let data: String
    let ttl: Int?
    let priority: Int?
    let service: String?
    let recordProtocol: String?
    let port: Int?
    let weight: Int?

    enum CodingKeys: String, CodingKey {
        case type, name, data, ttl, priority, service, port, weight
        case recordProtocol = "protocol"
    }
}

struct GoDaddyWriteRecord: Codable, Equatable {
    let type: String?
    let name: String?
    let data: String
    let ttl: Int
    let priority: Int?
    let service: String?
    let recordProtocol: String?
    let port: Int?
    let weight: Int?

    enum CodingKeys: String, CodingKey {
        case type, name, data, ttl, priority, service, port, weight
        case recordProtocol = "protocol"
    }

    func replacingTypeAndName() -> GoDaddyWriteRecord {
        GoDaddyWriteRecord(
            type: nil,
            name: nil,
            data: data,
            ttl: ttl,
            priority: priority,
            service: service,
            recordProtocol: recordProtocol,
            port: port,
            weight: weight
        )
    }
}

struct GoDaddyRecordSet: Codable, Hashable {
    let nativeName: String
    let type: String
    let service: String?
    let recordProtocol: String?
    let records: [GoDaddyDNSRecord]

    var displayName: String {
        guard type.uppercased() == "SRV", let service, let recordProtocol else { return nativeName }
        let prefix = "\(service).\(recordProtocol)"
        if nativeName == "@" || nativeName.isEmpty { return prefix }
        if nativeName == prefix || nativeName.hasPrefix("\(prefix).") { return nativeName }
        return "\(prefix).\(nativeName)"
    }

    var sharedPriority: Int? {
        guard type.uppercased() == "MX" || type.uppercased() == "SRV" else { return nil }
        let priorities = records.compactMap(\.priority)
        return priorities.count == records.count && Set(priorities).count == 1 ? priorities.first : nil
    }

    var sharedTTL: Int? {
        let values = records.compactMap(\.ttl)
        return values.count == records.count && Set(values).count == 1 ? values.first : nil
    }

    var displayValues: [String] {
        switch type.uppercased() {
        case "MX":
            if sharedPriority != nil { return records.map(\.data) }
            return records.map { "\($0.priority ?? 0) \($0.data)" }
        case "SRV":
            if sharedPriority != nil {
                return records.map { "\($0.weight ?? 0) \($0.port ?? 0) \($0.data)" }
            }
            return records.map { "\($0.priority ?? 0) \($0.weight ?? 0) \($0.port ?? 0) \($0.data)" }
        default:
            return records.map(\.data)
        }
    }

    func snapshot() -> ProviderRecordSnapshot {
        var metadata = [
            "nativeName": nativeName,
            "valueCount": String(records.count),
        ]
        if let service { metadata["service"] = service }
        if let recordProtocol { metadata["protocol"] = recordProtocol }
        return ProviderRecordSnapshot(
            id: [nativeName, type.uppercased(), service ?? "", recordProtocol ?? ""].joined(separator: "|"),
            name: displayName,
            type: type,
            values: displayValues,
            ttl: sharedTTL,
            priority: sharedPriority,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }

    func matchesIdentity(of record: GoDaddyDNSRecord) -> Bool {
        guard record.type.caseInsensitiveCompare(type) == .orderedSame,
              record.name.caseInsensitiveCompare(nativeName) == .orderedSame
        else {
            return false
        }
        guard type.uppercased() == "SRV" else { return true }
        return record.service?.caseInsensitiveCompare(service ?? "") == .orderedSame &&
            record.recordProtocol?.caseInsensitiveCompare(recordProtocol ?? "") == .orderedSame
    }
}

struct GoDaddyRecordMutation {
    let nativeName: String
    let type: String
    let service: String?
    let recordProtocol: String?
    let records: [GoDaddyWriteRecord]

    func matchesIdentity(of record: GoDaddyDNSRecord) -> Bool {
        guard record.type.caseInsensitiveCompare(type) == .orderedSame,
              record.name.caseInsensitiveCompare(nativeName) == .orderedSame
        else {
            return false
        }
        guard type == "SRV" else { return true }
        return record.service?.caseInsensitiveCompare(service ?? "") == .orderedSame &&
            record.recordProtocol?.caseInsensitiveCompare(recordProtocol ?? "") == .orderedSame
    }
}

func goDaddyRecordSets(from records: [GoDaddyDNSRecord]) -> [GoDaddyRecordSet] {
    struct Key: Hashable {
        let name: String
        let type: String
        let service: String?
        let recordProtocol: String?
    }

    let grouped = Dictionary(grouping: records) { record in
        let type = record.type.uppercased()
        return Key(
            name: record.name,
            type: type,
            service: type == "SRV" ? record.service : nil,
            recordProtocol: type == "SRV" ? record.recordProtocol : nil
        )
    }

    return grouped.map { key, values in
        GoDaddyRecordSet(
            nativeName: key.name,
            type: key.type,
            service: key.service,
            recordProtocol: key.recordProtocol,
            records: values
        )
    }
    .sorted {
        if $0.displayName == $1.displayName { return $0.type < $1.type }
        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
}

extension CreateProviderRecordRequest {
    func toGoDaddyMutation(zoneName: String) throws -> GoDaddyRecordMutation {
        let type = type.uppercased()
        try validateGoDaddyRecordType(type)
        let identity = try goDaddyIdentity(name: name, type: type, zoneName: zoneName)
        let values = values ?? [recordData?.flatContent ?? content]
        let ttl = DNSProvider.goDaddy.normalizeTTL(ttl) ?? DNSProvider.goDaddy.defaultTTL
        return try GoDaddyRecordMutation(
            nativeName: identity.name,
            type: type,
            service: identity.service,
            recordProtocol: identity.recordProtocol,
            records: values.map {
                try goDaddyWriteRecord(
                    type: type,
                    identity: identity,
                    value: $0,
                    ttl: ttl,
                    priority: priority,
                    recordData: recordData
                )
            }
        )
    }
}

extension UpdateProviderRecordRequest {
    func toGoDaddyMutation(zoneName: String, existing: GoDaddyRecordSet) throws -> GoDaddyRecordMutation {
        let type = (type ?? existing.type).uppercased()
        try validateGoDaddyRecordType(type)
        let identity = try goDaddyIdentity(name: name ?? existing.displayName, type: type, zoneName: zoneName)
        let hasValueEdit = values != nil || content != nil || recordData != nil || type != existing.type.uppercased()

        if !hasValueEdit {
            let records = existing.records.map { record in
                GoDaddyWriteRecord(
                    type: type,
                    name: identity.name,
                    data: record.data,
                    ttl: DNSProvider.goDaddy.normalizeTTL(ttl ?? record.ttl) ?? DNSProvider.goDaddy.defaultTTL,
                    priority: (type == "MX" || type == "SRV") ? priority ?? record.priority : nil,
                    service: type == "SRV" ? identity.service : nil,
                    recordProtocol: type == "SRV" ? identity.recordProtocol : nil,
                    port: type == "SRV" ? record.port : nil,
                    weight: type == "SRV" ? record.weight : nil
                )
            }
            return GoDaddyRecordMutation(
                nativeName: identity.name,
                type: type,
                service: identity.service,
                recordProtocol: identity.recordProtocol,
                records: records
            )
        }

        let values: [String] = if let values {
            values
        } else if let recordData, let flatContent = recordData.flatContent {
            [flatContent]
        } else if let content {
            [content]
        } else {
            existing.displayValues
        }
        let mutationTTL = DNSProvider.goDaddy.normalizeTTL(
            ttl ?? existing.sharedTTL ?? existing.records.first?.ttl
        ) ??
            DNSProvider.goDaddy.defaultTTL
        return try GoDaddyRecordMutation(
            nativeName: identity.name,
            type: type,
            service: identity.service,
            recordProtocol: identity.recordProtocol,
            records: values.map {
                try goDaddyWriteRecord(
                    type: type,
                    identity: identity,
                    value: $0,
                    ttl: mutationTTL,
                    priority: priority ?? existing.sharedPriority,
                    recordData: recordData
                )
            }
        )
    }
}

private struct GoDaddyRecordIdentity {
    let name: String
    let service: String?
    let recordProtocol: String?
}

private func goDaddyIdentity(name: String, type: String, zoneName: String) throws -> GoDaddyRecordIdentity {
    let relativeName = ProviderDNSName.relativeAtCaseInsensitive(name, zoneName: zoneName)
    guard type == "SRV" else {
        return GoDaddyRecordIdentity(name: relativeName, service: nil, recordProtocol: nil)
    }

    let parts = relativeName.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
    guard parts.count >= 2, parts[0].hasPrefix("_"), parts[1].hasPrefix("_") else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .goDaddy,
            type: type,
            message: "the name must begin with _service._protocol"
        )
    }
    return GoDaddyRecordIdentity(
        name: parts.count > 2 ? parts.dropFirst(2).joined(separator: ".") : "@",
        service: parts[0],
        recordProtocol: parts[1]
    )
}

private func goDaddyWriteRecord(
    type: String,
    identity: GoDaddyRecordIdentity,
    value: String,
    ttl: Int,
    priority: Int?,
    recordData: RecordData?
) throws -> GoDaddyWriteRecord {
    if type == "MX" {
        let parts = value.split(whereSeparator: \Character.isWhitespace)
        let embeddedPriority = parts.first.flatMap { Int($0) }
        let target = embeddedPriority == nil ? value : parts.dropFirst().joined(separator: " ")
        return try GoDaddyWriteRecord(
            type: type,
            name: identity.name,
            data: target,
            ttl: ttl,
            priority: goDaddyUInt16(embeddedPriority ?? recordData?.priority ?? priority ?? 10, field: "priority"),
            service: nil,
            recordProtocol: nil,
            port: nil,
            weight: nil
        )
    }

    if type == "SRV" {
        let parsed: (priority: Int, weight: Int, port: Int, target: String)
        if let recordData, let weight = recordData.weight, let port = recordData.port, let target = recordData.target {
            parsed = (recordData.priority ?? priority ?? 0, weight, port, target)
        } else {
            let parts = value.split(whereSeparator: \Character.isWhitespace)
            if parts.count >= 4,
               let embeddedPriority = Int(parts[0]),
               let weight = Int(parts[1]),
               let port = Int(parts[2])
            {
                parsed = (embeddedPriority, weight, port, parts.dropFirst(3).joined(separator: " "))
            } else if parts.count >= 3, let weight = Int(parts[0]), let port = Int(parts[1]) {
                parsed = (priority ?? 0, weight, port, parts.dropFirst(2).joined(separator: " "))
            } else {
                throw ProviderAPIError.invalidRecordContent(
                    provider: .goDaddy,
                    type: type,
                    message: "expected priority, weight, port, and target, or a separate priority with weight, port, and target"
                )
            }
        }
        guard (1 ... 65535).contains(parsed.port) else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .goDaddy,
                type: type,
                message: "port must be from 1 through 65535"
            )
        }
        return try GoDaddyWriteRecord(
            type: type,
            name: identity.name,
            data: parsed.target,
            ttl: ttl,
            priority: goDaddyUInt16(parsed.priority, field: "priority"),
            service: identity.service,
            recordProtocol: identity.recordProtocol,
            port: parsed.port,
            weight: goDaddyUInt16(parsed.weight, field: "weight")
        )
    }

    return GoDaddyWriteRecord(
        type: type,
        name: identity.name,
        data: value,
        ttl: ttl,
        priority: nil,
        service: nil,
        recordProtocol: nil,
        port: nil,
        weight: nil
    )
}

private func goDaddyUInt16(_ value: Int, field: String) throws -> Int {
    guard (0 ... 65535).contains(value) else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .goDaddy,
            type: "SRV",
            message: "\(field) must be from 0 through 65535"
        )
    }
    return value
}

private func validateGoDaddyRecordType(_ type: String) throws {
    guard DNSProvider.goDaddy.capabilities.canEdit(recordType: type) else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .goDaddy,
            type: type,
            message: "the record type is registrar-managed or unsupported by the current Domains API"
        )
    }
}
