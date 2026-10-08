import Foundation

struct DigitalOceanDomain: Codable, Hashable {
    let name: String
    let ttl: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case ttl
    }

    func snapshot(nameservers: [String]) -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: name,
            name: name,
            nameservers: nameservers,
            metadata: ttl.map { ["ttl": String($0)] } ?? [:],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct DigitalOceanDomainRecord: Codable, Hashable {
    let id: Int
    let type: String
    let name: String
    let data: String
    let priority: Int?
    let port: Int?
    let ttl: Int?
    let weight: Int?
    let flags: Int?
    let tag: String?

    func snapshot() -> ProviderRecordSnapshot {
        var metadata: [String: String] = [:]
        if let port { metadata["port"] = String(port) }
        if let weight { metadata["weight"] = String(weight) }
        if let flags { metadata["flags"] = String(flags) }
        if let tag { metadata["tag"] = tag }

        let content = switch type.uppercased() {
        case "SRV": "\(priority ?? 0) \(weight ?? 0) \(port ?? 0) \(data)"
        case "CAA": "\(flags ?? 0) \(tag ?? "") \(data)"
        default: data
        }

        return ProviderRecordSnapshot(
            id: String(id),
            name: name,
            type: type,
            values: [content],
            ttl: ttl,
            priority: priority,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct DigitalOceanCreateDomainRequest: Codable, Equatable {
    let name: String
}

struct DigitalOceanRecordWriteRequest: Codable, Equatable {
    let type: String
    let name: String
    let data: String
    let priority: Int?
    let port: Int?
    let ttl: Int?
    let weight: Int?
    let flags: Int?
    let tag: String?
}

struct DigitalOceanDomainEnvelope: Decodable {
    let domain: DigitalOceanDomain
}

struct DigitalOceanDomainsEnvelope: Decodable {
    let domains: [DigitalOceanDomain]
    let links: DigitalOceanLinks?
}

struct DigitalOceanDomainRecordEnvelope: Decodable {
    let domainRecord: DigitalOceanDomainRecord

    enum CodingKeys: String, CodingKey {
        case domainRecord = "domain_record"
    }
}

struct DigitalOceanDomainRecordsEnvelope: Decodable {
    let domainRecords: [DigitalOceanDomainRecord]
    let links: DigitalOceanLinks?

    enum CodingKeys: String, CodingKey {
        case domainRecords = "domain_records"
        case links
    }
}

struct DigitalOceanLinks: Decodable {
    struct Pages: Decodable {
        let first: URL?
        let previous: URL?
        let next: URL?
        let last: URL?

        enum CodingKeys: String, CodingKey {
            case first
            case previous = "prev"
            case next
            case last
        }
    }

    let pages: Pages?
}

extension CreateProviderRecordRequest {
    func toDigitalOceanRequest(zoneName: String) throws -> DigitalOceanRecordWriteRequest {
        try DigitalOceanRecordWriteRequest(
            type: type.uppercased(),
            name: ProviderDNSName.relativeAt(name, zoneName: zoneName),
            content: recordData?.flatContent ?? content,
            ttl: DNSProvider.digitalOcean.normalizeTTL(ttl),
            priority: priority,
            recordData: recordData,
            provider: .digitalOcean
        )
    }
}

extension UpdateProviderRecordRequest {
    func toDigitalOceanRequest(
        zoneName: String,
        existingRecord: DigitalOceanDomainRecord
    ) throws -> DigitalOceanRecordWriteRequest {
        let resolvedType = (type ?? existingRecord.type).uppercased()
        let resolvedName = ProviderDNSName.relativeAt(name ?? existingRecord.name, zoneName: zoneName)
        let resolvedContent = recordData?.flatContent ?? content ?? values?.first ?? existingRecord.snapshot().content

        return try DigitalOceanRecordWriteRequest(
            type: resolvedType,
            name: resolvedName,
            content: resolvedContent,
            ttl: DNSProvider.digitalOcean.normalizeTTL(ttl ?? existingRecord.ttl),
            priority: priority ?? existingRecord.priority,
            recordData: recordData,
            existingRecord: existingRecord,
            provider: .digitalOcean
        )
    }
}

private extension DigitalOceanRecordWriteRequest {
    init(
        type: String,
        name: String,
        content: String,
        ttl: Int?,
        priority: Int?,
        recordData: RecordData?,
        existingRecord: DigitalOceanDomainRecord? = nil,
        provider: DNSProvider
    ) throws {
        var resolvedData = content
        var resolvedPriority = priority
        var resolvedPort: Int?
        var resolvedWeight: Int?
        var resolvedFlags: Int?
        var resolvedTag: String?

        switch type {
        case "SRV":
            if let recordData {
                resolvedData = recordData.target ?? ""
                resolvedPriority = recordData.priority ?? priority
                resolvedPort = recordData.port
                resolvedWeight = recordData.weight
            } else {
                let parts = content.split(whereSeparator: \Character.isWhitespace)
                guard parts.count >= 4,
                      let parsedPriority = Int(parts[0]),
                      let parsedWeight = Int(parts[1]),
                      let parsedPort = Int(parts[2])
                else {
                    throw ProviderAPIError.invalidRecordContent(
                        provider: provider,
                        type: type,
                        message: "expected priority, weight, port, and target"
                    )
                }
                resolvedPriority = parsedPriority
                resolvedWeight = parsedWeight
                resolvedPort = parsedPort
                resolvedData = parts.dropFirst(3).joined(separator: " ")
            }
        case "CAA":
            if let recordData {
                resolvedData = recordData.value ?? ""
                resolvedFlags = recordData.flags
                resolvedTag = recordData.tag
            } else {
                let parts = content.split(maxSplits: 2, whereSeparator: \Character.isWhitespace)
                guard parts.count == 3, let flags = Int(parts[0]) else {
                    throw ProviderAPIError.invalidRecordContent(
                        provider: provider,
                        type: type,
                        message: "expected flags, tag, and value"
                    )
                }
                resolvedFlags = flags
                resolvedTag = String(parts[1])
                resolvedData = String(parts[2]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        default:
            break
        }

        if type == "SRV", recordData == nil, content.isEmpty, let existingRecord {
            resolvedData = existingRecord.data
            resolvedPriority = existingRecord.priority
            resolvedPort = existingRecord.port
            resolvedWeight = existingRecord.weight
        }
        if type == "CAA", recordData == nil, content.isEmpty, let existingRecord {
            resolvedData = existingRecord.data
            resolvedFlags = existingRecord.flags
            resolvedTag = existingRecord.tag
        }
        if ["CNAME", "MX", "NS", "SRV"].contains(type) {
            resolvedData = Self.fullyQualifiedTarget(resolvedData)
        }

        self.init(
            type: type,
            name: name,
            data: resolvedData,
            priority: resolvedPriority,
            port: resolvedPort,
            ttl: ttl,
            weight: resolvedWeight,
            flags: resolvedFlags,
            tag: resolvedTag
        )
    }

    static func fullyQualifiedTarget(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != ".", !value.hasSuffix(".") else { return value }
        return "\(value)."
    }
}
