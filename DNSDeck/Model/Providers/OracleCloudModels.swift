import Foundation

struct OracleCloudNameserver: Codable, Hashable {
    let hostname: String
}

struct OracleCloudZone: Codable, Hashable {
    let name: String
    let zoneType: String
    let compartmentId: String
    let scope: String
    let freeformTags: [String: String]?
    let definedTags: [String: [String: ProviderJSONValue]]?
    let resolutionMode: String?
    let dnssecState: String?
    let `self`: String?
    let id: String
    let timeCreated: String?
    let version: String?
    let serial: Int?
    let lifecycleState: String
    let isProtected: Bool
    let nameservers: [OracleCloudNameserver]?
    let viewId: String?
    var etag: String?

    var isWritablePublicPrimary: Bool {
        scope.caseInsensitiveCompare("GLOBAL") == .orderedSame &&
            zoneType.caseInsensitiveCompare("PRIMARY") == .orderedSame && !isProtected
    }

    func snapshot() -> ProviderZoneSnapshot {
        var metadata: [String: String] = [
            "compartmentId": compartmentId,
            "scope": scope,
            "zoneType": zoneType,
        ]
        if let version { metadata["version"] = version }
        if let serial { metadata["serial"] = String(serial) }
        if let dnssecState { metadata["dnssecState"] = dnssecState }
        if let resolutionMode { metadata["resolutionMode"] = resolutionMode }
        if isProtected { metadata["isProtected"] = "true" }
        for (key, value) in freeformTags ?? [:] {
            metadata["tag.\(key)"] = value
        }

        return ProviderZoneSnapshot(
            id: id,
            name: name.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            nameservers: nameservers?.map(\.hostname) ?? [],
            status: lifecycleState,
            createdOn: timeCreated.flatMap(DateFormatter.iso8601.date),
            etag: etag,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct OracleCloudCreateZoneRequest: Codable, Equatable {
    let name: String
    let compartmentId: String
    let zoneType: String
    let scope: String
    let migrationSource: String
}

struct OracleCloudRecord: Codable, Hashable {
    let domain: String
    let recordHash: String?
    let isProtected: Bool?
    let rdata: String
    let rrsetVersion: String?
    let rtype: String
    let ttl: Int
}

struct OracleCloudRecordCollection: Codable, Equatable {
    let items: [OracleCloudRecord]
}

struct OracleCloudRRSet: Codable, Hashable {
    let domain: String
    let type: String
    let items: [OracleCloudRecord]
    var etag: String?

    var isProtected: Bool {
        items.contains { $0.isProtected == true }
    }

    func snapshot() -> ProviderRecordSnapshot {
        let type = type.uppercased()
        let values = items.map { type == "TXT" ? oracleCloudParseTXT($0.rdata) : $0.rdata }
        var metadata: [String: String] = [:]
        let versions = Set(items.compactMap(\.rrsetVersion))
        if versions.count == 1 { metadata["rrsetVersion"] = versions.first }
        if isProtected { metadata["isProtected"] = "true" }
        let alias = type == "ALIAS" ? values.first.map {
            DNSAliasTarget(name: $0, zoneId: nil, evaluateTargetHealth: nil)
        } : nil

        return ProviderRecordSnapshot(
            id: "\(domain.lowercased())|\(type)",
            name: domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            type: type,
            values: values,
            ttl: items.first?.ttl,
            priority: priority,
            aliasTarget: alias,
            etag: etag,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }

    var priority: Int? {
        guard items.count == 1, type.uppercased() == "MX" || type.uppercased() == "SRV" else { return nil }
        return items.first?.rdata.split(whereSeparator: \Character.isWhitespace).first.flatMap { Int($0) }
    }

    static func grouped(_ records: [OracleCloudRecord]) -> [OracleCloudRRSet] {
        struct Key: Hashable {
            let domain: String
            let type: String
        }

        let grouped = Dictionary(grouping: records) {
            Key(domain: $0.domain.lowercased(), type: $0.rtype.uppercased())
        }
        return grouped.map { key, records in
            OracleCloudRRSet(
                domain: records.first?.domain ?? key.domain,
                type: key.type,
                items: records.sorted { $0.rdata < $1.rdata },
                etag: nil
            )
        }
        .sorted {
            if $0.domain.caseInsensitiveCompare($1.domain) == .orderedSame {
                return $0.type < $1.type
            }
            return $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending
        }
    }
}

struct OracleCloudRecordDetails: Codable, Hashable {
    let domain: String
    let rdata: String
    let rtype: String
    let ttl: Int
}

struct OracleCloudUpdateRRSetRequest: Codable, Equatable {
    let items: [OracleCloudRecordDetails]
}

struct OracleCloudRRSetMutation: Equatable {
    let domain: String
    let type: String
    let request: OracleCloudUpdateRRSetRequest
}

extension CreateProviderRecordRequest {
    func toOracleCloudMutation(zoneName: String) throws -> OracleCloudRRSetMutation {
        let type = type.uppercased()
        try validateOracleCloudRecordType(type)
        let values = values ?? [aliasTarget ?? recordData?.flatContent ?? content]
        try validateOracleCloudCardinality(type: type, count: values.count)
        let domain = oracleCloudAbsoluteName(name, zoneName: zoneName)
        let ttl = DNSProvider.oracleCloud.getEffectiveTTL(ttl) ?? DNSProvider.oracleCloud.defaultTTL
        let rdata = try values.map {
            try oracleCloudRData(
                type: type,
                value: $0,
                priority: priority,
                recordData: recordData
            )
        }
        return OracleCloudRRSetMutation(
            domain: domain,
            type: type,
            request: OracleCloudUpdateRRSetRequest(
                items: rdata.map { OracleCloudRecordDetails(domain: domain, rdata: $0, rtype: type, ttl: ttl) }
            )
        )
    }
}

extension UpdateProviderRecordRequest {
    func toOracleCloudMutation(zoneName: String, existing: OracleCloudRRSet) throws -> OracleCloudRRSetMutation {
        let type = (type ?? existing.type).uppercased()
        try validateOracleCloudRecordType(type)
        let domain = oracleCloudAbsoluteName(name ?? existing.domain, zoneName: zoneName)
        let ttl = DNSProvider.oracleCloud.normalizeTTL(ttl ?? existing.items.first?.ttl) ??
            DNSProvider.oracleCloud.defaultTTL
        let changesRecordData = values != nil || content != nil || recordData != nil || aliasTarget != nil ||
            type.caseInsensitiveCompare(existing.type) != .orderedSame
        let details: [OracleCloudRecordDetails]

        if changesRecordData {
            let values = values ?? aliasTarget.map { [$0] } ?? content.map { [$0] } ??
                recordData?.flatContent.map { [$0] } ?? existing.snapshot().values
            details = try values.map {
                try OracleCloudRecordDetails(
                    domain: domain,
                    rdata: oracleCloudRData(
                        type: type,
                        value: $0,
                        priority: priority ?? existing.priority,
                        recordData: recordData
                    ),
                    rtype: type,
                    ttl: ttl
                )
            }
        } else {
            details = existing.items.map {
                OracleCloudRecordDetails(domain: domain, rdata: $0.rdata, rtype: type, ttl: ttl)
            }
        }
        try validateOracleCloudCardinality(type: type, count: details.count)

        return OracleCloudRRSetMutation(
            domain: domain,
            type: type,
            request: OracleCloudUpdateRRSetRequest(items: details)
        )
    }
}

private func validateOracleCloudRecordType(_ type: String) throws {
    guard DNSProvider.oracleCloud.capabilities.canEdit(recordType: type) else {
        throw oracleCloudInvalid(type, "the record type is provider-managed or unsupported by OCI DNS")
    }
}

private func validateOracleCloudCardinality(type: String, count: Int) throws {
    guard count > 0 else {
        throw oracleCloudInvalid(type, "an RRset must contain at least one record")
    }
    if ["ALIAS", "CNAME", "DNAME"].contains(type), count != 1 {
        throw oracleCloudInvalid(type, "this RRset type must contain exactly one record")
    }
}

private func oracleCloudRData(
    type: String,
    value: String,
    priority: Int?,
    recordData: RecordData?
) throws -> String {
    switch type {
    case "CAA":
        if let recordData,
           let flags = recordData.flags,
           let tag = recordData.tag,
           let value = recordData.value
        {
            guard (0 ... 255).contains(flags) else {
                throw oracleCloudInvalid(type, "flags must be between 0 and 255")
            }
            return "\(flags) \(tag) \(value.oracleCloudQuoted)"
        }
    case "MX":
        let parts = value.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
        if parts.first.flatMap({ Int($0) }) != nil { return value }
        guard let priority = recordData?.priority ?? priority, (0 ... 65535).contains(priority) else {
            throw oracleCloudInvalid(type, "expected a preference from 0 through 65535 and an exchange")
        }
        return "\(priority) \(recordData?.target ?? value)"
    case "SRV":
        if let recordData,
           let weight = recordData.weight,
           let port = recordData.port,
           let target = recordData.target
        {
            let priority = recordData.priority ?? priority ?? 0
            try validateOracleCloudSRV(priority: priority, weight: weight, port: port)
            return "\(priority) \(weight) \(port) \(target)"
        }
        let parts = value.split(maxSplits: 3, whereSeparator: \Character.isWhitespace)
        guard parts.count == 4,
              let priority = Int(parts[0]),
              let weight = Int(parts[1]),
              let port = Int(parts[2])
        else {
            throw oracleCloudInvalid(type, "expected priority, weight, port, and target")
        }
        try validateOracleCloudSRV(priority: priority, weight: weight, port: port)
    case "TXT":
        return oracleCloudFormatTXT(oracleCloudParseTXT(value))
    default:
        break
    }
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw oracleCloudInvalid(type, "record data must not be empty")
    }
    return value
}

private func validateOracleCloudSRV(priority: Int, weight: Int, port: Int) throws {
    guard (0 ... 65535).contains(priority),
          (0 ... 65535).contains(weight),
          (0 ... 65535).contains(port)
    else {
        throw oracleCloudInvalid("SRV", "priority, weight, and port must be between 0 and 65535")
    }
}

private func oracleCloudInvalid(_ type: String, _ message: String) -> ProviderAPIError {
    ProviderAPIError.invalidRecordContent(provider: .oracleCloud, type: type, message: message)
}

private func oracleCloudAbsoluteName(_ name: String, zoneName: String) -> String {
    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    let zone = zoneName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    if value.isEmpty || value == "@" || value.caseInsensitiveCompare(zone) == .orderedSame { return "\(zone)." }
    let suffix = ".\(zone)"
    let absolute = value.lowercased().hasSuffix(suffix.lowercased()) ? value : "\(value).\(zone)"
    return "\(absolute)."
}

private func oracleCloudFormatTXT(_ value: String) -> String {
    var chunks: [String] = []
    var current = ""
    var byteCount = 0

    for character in value {
        let fragment = String(character)
        let fragmentBytes = fragment.utf8.count
        if byteCount + fragmentBytes > 255, !current.isEmpty {
            chunks.append(current)
            current = ""
            byteCount = 0
        }
        current.append(character)
        byteCount += fragmentBytes
    }
    if !current.isEmpty || chunks.isEmpty { chunks.append(current) }
    return chunks.map(\.oracleCloudQuoted).joined(separator: " ")
}

private func oracleCloudParseTXT(_ value: String) -> String {
    guard value.contains("\"") else { return value }
    var result = ""
    var isQuoted = false
    var isEscaped = false

    for character in value {
        if isEscaped {
            result.append(character)
            isEscaped = false
        } else if character == "\\" {
            isEscaped = true
        } else if character == "\"" {
            isQuoted.toggle()
        } else if isQuoted {
            result.append(character)
        }
    }
    return result.isEmpty && value != "\"\"" ? value : result
}

private extension String {
    var oracleCloudQuoted: String {
        let escaped = replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
