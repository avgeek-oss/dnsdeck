import Foundation

struct HetznerZone: Codable, Hashable {
    struct AuthoritativeNameservers: Codable, Hashable {
        let assigned: [String]
        let delegated: [String]?
        let delegationStatus: String?

        enum CodingKeys: String, CodingKey {
            case assigned
            case delegated
            case delegationStatus = "delegation_status"
        }
    }

    struct Protection: Codable, Hashable {
        let delete: Bool
    }

    let id: Int64
    let name: String
    let created: String?
    let ttl: Int?
    let mode: String?
    let protection: Protection?
    let labels: [String: String]?
    let authoritativeNameservers: AuthoritativeNameservers?
    let registrar: String?
    let status: String?
    let recordCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case created
        case ttl
        case mode
        case protection
        case labels
        case authoritativeNameservers = "authoritative_nameservers"
        case registrar
        case status
        case recordCount = "record_count"
    }

    func snapshot() -> ProviderZoneSnapshot {
        var metadata: [String: String] = [:]
        if let ttl { metadata["ttl"] = String(ttl) }
        if let mode { metadata["mode"] = mode }
        if let registrar { metadata["registrar"] = registrar }
        if let recordCount { metadata["recordCount"] = String(recordCount) }
        if let delegationStatus = authoritativeNameservers?.delegationStatus {
            metadata["delegationStatus"] = delegationStatus
        }
        if protection?.delete == true { metadata["deleteProtected"] = "true" }

        return ProviderZoneSnapshot(
            id: String(id),
            name: name,
            nameservers: authoritativeNameservers?.assigned ?? [],
            status: status,
            createdOn: created.flatMap(ProviderRecordValue.date),
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct HetznerRRSet: Codable, Hashable {
    struct Protection: Codable, Hashable {
        let change: Bool
    }

    let id: String
    let name: String
    let type: String
    let ttl: Int?
    let labels: [String: String]?
    let protection: Protection?
    let records: [HetznerRRSetRecord]
    let zone: Int64?

    func snapshot() -> ProviderRecordSnapshot {
        let providerValues = records.map(\.value)
        let displayValues = providerValues.map { value in
            if type.uppercased() == "TXT" {
                return ProviderRecordValue.parseQuotedTXT(value)
            }
            if type.uppercased() == "MX", providerValues.count == 1 {
                return ProviderRecordValue.removingPriority(value)
            }
            return value
        }
        var metadata: [String: String] = [:]
        if let zone { metadata["zoneId"] = String(zone) }
        if protection?.change == true { metadata["changeProtected"] = "true" }
        if let labels, !labels.isEmpty { metadata["labelCount"] = String(labels.count) }

        return ProviderRecordSnapshot(
            id: id,
            name: name,
            type: type,
            values: displayValues,
            ttl: ttl,
            priority: type.uppercased() == "MX" && providerValues.count == 1
                ? providerValues.first.flatMap(ProviderRecordValue.priority)
                : nil,
            comment: records.count == 1 ? records.first?.comment : nil,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct HetznerRRSetRecord: Codable, Hashable {
    let value: String
    let comment: String?

    init(value: String, comment: String? = nil) {
        self.value = value
        self.comment = comment?.isEmpty == true ? nil : comment
    }
}

struct HetznerAction: Codable, Hashable {
    struct ActionError: Codable, Hashable {
        let code: String?
        let message: String?
    }

    let id: Int64
    let status: String?
    let command: String?
    let progress: Int?
    let error: ActionError?
}

struct HetznerPaginationEnvelope: Decodable {
    struct Meta: Decodable {
        struct Pagination: Decodable {
            let page: Int?
            let nextPage: Int?
            let lastPage: Int?

            enum CodingKeys: String, CodingKey {
                case page
                case nextPage = "next_page"
                case lastPage = "last_page"
            }
        }

        let pagination: Pagination?
    }

    let meta: Meta?
}

struct HetznerZonesEnvelope: Decodable {
    let zones: [HetznerZone]
    let meta: HetznerPaginationEnvelope.Meta?
}

struct HetznerZoneEnvelope: Decodable {
    let zone: HetznerZone
}

struct HetznerRRSetsEnvelope: Decodable {
    let rrsets: [HetznerRRSet]
    let meta: HetznerPaginationEnvelope.Meta?
}

struct HetznerActionEnvelope: Decodable {
    let action: HetznerAction
}

struct HetznerZoneCreateEnvelope: Decodable {
    let zone: HetznerZone
    let action: HetznerAction
}

struct HetznerRRSetCreateEnvelope: Decodable {
    let rrset: HetznerRRSet
    let action: HetznerAction
}

struct HetznerCreateZoneRequest: Codable, Equatable {
    let name: String
    let mode: String
    let ttl: Int
}

struct HetznerCreateRRSetRequest: Codable, Equatable {
    let name: String
    let type: String
    let ttl: Int?
    var labels: [String: String]? = nil
    let records: [HetznerRRSetRecord]
}

struct HetznerSetRecordsRequest: Codable, Equatable {
    let records: [HetznerRRSetRecord]
}

struct HetznerChangeTTLRequest: Codable, Equatable {
    let ttl: Int?

    enum CodingKeys: String, CodingKey {
        case ttl
    }

    init(ttl: Int?) {
        self.ttl = ttl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ttl = try container.decodeIfPresent(Int.self, forKey: .ttl)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let ttl {
            try container.encode(ttl, forKey: .ttl)
        } else {
            try container.encodeNil(forKey: .ttl)
        }
    }
}

struct HetznerRRSetDesiredState {
    let name: String
    let type: String
    let ttl: Int?
    let labels: [String: String]?
    let records: [HetznerRRSetRecord]
    let identityChanged: Bool
    let recordsChanged: Bool
    let ttlChanged: Bool
}

extension CreateProviderRecordRequest {
    func toHetznerRequest(zoneName: String) -> HetznerCreateRRSetRequest {
        let resolvedType = type.uppercased()
        let rawValues = values ?? [recordData?.flatContent ?? content]
        let resolvedValues = rawValues.map {
            hetznerWriteValue(type: resolvedType, value: $0, priority: priority)
        }
        let records = resolvedValues.enumerated().map { index, value in
            HetznerRRSetRecord(value: value, comment: index == 0 ? comment : nil)
        }

        return HetznerCreateRRSetRequest(
            name: ProviderDNSName.relativeAt(name, zoneName: zoneName),
            type: resolvedType,
            ttl: DNSProvider.hetzner.normalizeTTL(ttl),
            labels: nil,
            records: records
        )
    }
}

extension UpdateProviderRecordRequest {
    func toHetznerState(zoneName: String, existing: HetznerRRSet) -> HetznerRRSetDesiredState {
        let resolvedName = ProviderDNSName.relativeAt(name ?? existing.name, zoneName: zoneName)
        let resolvedType = (type ?? existing.type).uppercased()
        let recordsChanged = content != nil || values != nil || recordData != nil || priority != nil || comment != nil
        let existingPriority = existing.records.count == 1
            ? existing.records.first.flatMap { ProviderRecordValue.priority($0.value) }
            : nil
        let resolvedPriority = priority ?? existingPriority

        let records: [HetznerRRSetRecord]
        if recordsChanged {
            let rawValues = values ?? [recordData?.flatContent ?? content ?? existing.records.first?.value ?? ""]
            records = rawValues.map { value in
                let resolvedValue = hetznerWriteValue(
                    type: resolvedType,
                    value: value,
                    priority: resolvedPriority
                )
                let matchingComment = existing.records.first(where: { $0.value == resolvedValue })?.comment
                return HetznerRRSetRecord(value: resolvedValue, comment: comment ?? matchingComment)
            }
        } else {
            records = existing.records
        }

        let resolvedTTL: Int? = if let ttl {
            DNSProvider.hetzner.normalizeTTL(ttl)
        } else {
            existing.ttl
        }

        return HetznerRRSetDesiredState(
            name: resolvedName,
            type: resolvedType,
            ttl: resolvedTTL,
            labels: existing.labels,
            records: records,
            identityChanged: resolvedName != existing.name || resolvedType != existing.type.uppercased(),
            recordsChanged: recordsChanged,
            ttlChanged: ttl != nil && resolvedTTL != existing.ttl
        )
    }
}

private func hetznerWriteValue(type: String, value: String, priority: Int?) -> String {
    switch type {
    case "MX":
        let parts = value.split(whereSeparator: \Character.isWhitespace)
        let parsedPriority = parts.first.flatMap { Int($0) }
        let target = parsedPriority == nil ? value : parts.dropFirst().joined(separator: " ")
        return "\(priority ?? parsedPriority ?? 10) \(target)"
    case "TXT":
        return formatHetznerTXT(value)
    default:
        return value
    }
}

private func formatHetznerTXT(_ value: String) -> String {
    if value.hasPrefix("\""), value.hasSuffix("\"") { return value }

    let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
    var chunks: [String] = []
    var current = ""
    var currentByteCount = 0

    for character in escaped {
        let characterBytes = String(character).utf8.count
        if currentByteCount + characterBytes > 255, !current.isEmpty {
            chunks.append(current)
            current = ""
            currentByteCount = 0
        }
        current.append(character)
        currentByteCount += characterBytes
    }
    if !current.isEmpty || chunks.isEmpty { chunks.append(current) }
    return chunks.map { "\"\($0)\"" }.joined(separator: " ")
}
