import Foundation

struct AkamaiCloudDomain: Codable, Hashable {
    let id: Int
    let domain: String
    let type: String
    let status: String?
    let description: String?
    let soaEmail: String?
    let retrySec: Int?
    let masterIPs: [String]?
    let axfrIPs: [String]?
    let tags: [String]?
    let expireSec: Int?
    let refreshSec: Int?
    let ttlSec: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case domain
        case type
        case status
        case description
        case soaEmail = "soa_email"
        case retrySec = "retry_sec"
        case masterIPs = "master_ips"
        case axfrIPs = "axfr_ips"
        case tags
        case expireSec = "expire_sec"
        case refreshSec = "refresh_sec"
        case ttlSec = "ttl_sec"
    }

    func snapshot(nameservers: [String]) -> ProviderZoneSnapshot {
        var metadata: [String: String] = ["type": type]
        if let soaEmail { metadata["soaEmail"] = soaEmail }
        if let ttlSec { metadata["ttl"] = String(ttlSec) }
        if let tags, !tags.isEmpty { metadata["tagCount"] = String(tags.count) }

        return ProviderZoneSnapshot(
            id: String(id),
            name: domain,
            nameservers: nameservers,
            status: status,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct AkamaiCloudDomainRecord: Codable, Hashable {
    let id: Int
    let type: String
    let name: String
    let target: String
    let priority: Int?
    let weight: Int?
    let port: Int?
    let service: String?
    let protocolValue: String?
    let ttlSec: Int?
    let tag: String?
    let created: String?
    let updated: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case target
        case priority
        case weight
        case port
        case service
        case protocolValue = "protocol"
        case ttlSec = "ttl_sec"
        case tag
        case created
        case updated
    }

    func snapshot(defaultTTL: Int) -> ProviderRecordSnapshot {
        let displayName: String
        let content: String

        switch type.uppercased() {
        case "SRV":
            let normalizedService = akamaiCloudUnderscored(service ?? "service")
            let normalizedProtocol = akamaiCloudUnderscored(protocolValue ?? "tcp")
            displayName = "\(normalizedService).\(normalizedProtocol)"
            content = "\(priority ?? 0) \(weight ?? 0) \(port ?? 0) \(target)"
        case "CAA":
            displayName = name.isEmpty ? "@" : name
            content = "0 \(tag ?? "issue") \(target)"
        default:
            displayName = name.isEmpty ? "@" : name
            content = target
        }

        var metadata: [String: String] = [:]
        if let weight { metadata["weight"] = String(weight) }
        if let port { metadata["port"] = String(port) }
        if let service { metadata["service"] = service }
        if let protocolValue { metadata["protocol"] = protocolValue }
        if let tag { metadata["tag"] = tag }

        return ProviderRecordSnapshot(
            id: String(id),
            name: displayName,
            type: type,
            values: [content],
            ttl: ttlSec == 0 ? defaultTTL : ttlSec,
            priority: type.uppercased() == "MX" ? priority : nil,
            createdOn: created.flatMap(akamaiCloudDate),
            modifiedOn: updated.flatMap(akamaiCloudDate),
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct AkamaiCloudPage<Item: Decodable>: Decodable {
    let data: [Item]
    let page: Int
    let pages: Int
    let results: Int?
}

struct AkamaiCloudCreateDomainRequest: Codable, Equatable {
    let domain: String
    let type: String
    let status: String
    let soaEmail: String
    let ttlSec: Int

    enum CodingKeys: String, CodingKey {
        case domain
        case type
        case status
        case soaEmail = "soa_email"
        case ttlSec = "ttl_sec"
    }
}

struct AkamaiCloudRecordWriteRequest: Codable, Equatable {
    let type: String?
    let name: String?
    let target: String?
    let priority: Int?
    let weight: Int?
    let port: Int?
    let service: String?
    let protocolValue: String?
    let ttlSec: Int?
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case target
        case priority
        case weight
        case port
        case service
        case protocolValue = "protocol"
        case ttlSec = "ttl_sec"
        case tag
    }
}

extension CreateProviderRecordRequest {
    func toAkamaiCloudRequest(zoneName: String) throws -> AkamaiCloudRecordWriteRequest {
        try akamaiCloudWriteRequest(
            provider: .akamaiCloud,
            type: type.uppercased(),
            name: name,
            zoneName: zoneName,
            content: recordData?.flatContent ?? content,
            ttl: ttl,
            priority: priority,
            recordData: recordData,
            existing: nil,
            includeType: true,
            nameWasProvided: true,
            contentWasProvided: true
        )
    }
}

extension UpdateProviderRecordRequest {
    func toAkamaiCloudRequest(
        zoneName: String,
        existing: AkamaiCloudDomainRecord
    ) throws -> AkamaiCloudRecordWriteRequest {
        try akamaiCloudWriteRequest(
            provider: .akamaiCloud,
            type: existing.type.uppercased(),
            name: name ?? existing.name,
            zoneName: zoneName,
            content: recordData?.flatContent ?? content ?? existing.snapshot(defaultTTL: 300).content,
            ttl: ttl,
            priority: priority ?? existing.priority,
            recordData: recordData,
            existing: existing,
            includeType: false,
            nameWasProvided: name != nil,
            contentWasProvided: content != nil
        )
    }
}

private func akamaiCloudWriteRequest(
    provider: DNSProvider,
    type: String,
    name: String,
    zoneName: String,
    content: String,
    ttl: Int?,
    priority: Int?,
    recordData: RecordData?,
    existing: AkamaiCloudDomainRecord?,
    includeType: Bool,
    nameWasProvided: Bool,
    contentWasProvided: Bool
) throws -> AkamaiCloudRecordWriteRequest {
    var resolvedName: String? = ProviderDNSName.relativeEmpty(name, zoneName: zoneName)
    var resolvedTarget = content
    var resolvedPriority = priority
    var resolvedWeight: Int?
    var resolvedPort: Int?
    var resolvedService: String?
    var resolvedProtocol: String?
    var resolvedTag: String?

    switch type {
    case "SRV":
        resolvedName = nil
        if let recordData {
            resolvedTarget = recordData.target ?? ""
            resolvedPriority = recordData.priority ?? priority
            resolvedWeight = recordData.weight
            resolvedPort = recordData.port
            resolvedService = akamaiCloudUnprefixed(recordData.service)
            resolvedProtocol = akamaiCloudUnprefixed(recordData.proto)
        } else if let existing, !contentWasProvided {
            resolvedTarget = existing.target
            resolvedPriority = priority ?? existing.priority
            resolvedWeight = existing.weight
            resolvedPort = existing.port
            if nameWasProvided {
                let nameParts = name.split(separator: ".")
                guard nameParts.count >= 2 else {
                    throw ProviderAPIError.invalidRecordContent(
                        provider: provider,
                        type: type,
                        message: "expected service and protocol in the record name"
                    )
                }
                resolvedService = akamaiCloudUnprefixed(String(nameParts[0]))
                resolvedProtocol = akamaiCloudUnprefixed(String(nameParts[1]))
            } else {
                resolvedService = akamaiCloudUnprefixed(existing.service)
                resolvedProtocol = akamaiCloudUnprefixed(existing.protocolValue)
            }
        } else {
            let parts = content.split(whereSeparator: \Character.isWhitespace)
            let nameParts = name.split(separator: ".")
            guard parts.count >= 4,
                  nameParts.count >= 2,
                  let parsedPriority = Int(parts[0]),
                  let parsedWeight = Int(parts[1]),
                  let parsedPort = Int(parts[2])
            else {
                throw ProviderAPIError.invalidRecordContent(
                    provider: provider,
                    type: type,
                    message: "expected service, protocol, priority, weight, port, and target"
                )
            }
            resolvedPriority = parsedPriority
            resolvedWeight = parsedWeight
            resolvedPort = parsedPort
            resolvedTarget = parts.dropFirst(3).joined(separator: " ")
            resolvedService = akamaiCloudUnprefixed(String(nameParts[0]))
            resolvedProtocol = akamaiCloudUnprefixed(String(nameParts[1]))
        }
    case "CAA":
        if let recordData {
            guard (recordData.flags ?? 0) == 0 else {
                throw ProviderAPIError.invalidRecordContent(
                    provider: provider,
                    type: type,
                    message: "Akamai Cloud supports CAA flags value 0 only"
                )
            }
            resolvedTarget = recordData.value ?? ""
            resolvedTag = recordData.tag
        } else if let existing, !contentWasProvided {
            resolvedTarget = existing.target
            resolvedTag = existing.tag
        } else {
            let parts = content.split(maxSplits: 2, whereSeparator: \Character.isWhitespace)
            guard parts.count == 3, Int(parts[0]) == 0 else {
                throw ProviderAPIError.invalidRecordContent(
                    provider: provider,
                    type: type,
                    message: "expected flags 0, tag, and value"
                )
            }
            resolvedTag = String(parts[1])
            resolvedTarget = String(parts[2]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
    case "MX":
        resolvedPriority = priority ?? existing?.priority ?? 0
    default:
        break
    }

    let resolvedTTL: Int? = if let ttl {
        DNSProvider.akamaiCloud.normalizeTTL(ttl)
    } else if let existing, existing.ttlSec != 0 {
        existing.ttlSec
    } else {
        nil
    }

    return AkamaiCloudRecordWriteRequest(
        type: includeType ? type : nil,
        name: resolvedName,
        target: resolvedTarget,
        priority: resolvedPriority,
        weight: resolvedWeight,
        port: resolvedPort,
        service: resolvedService,
        protocolValue: resolvedProtocol,
        ttlSec: resolvedTTL,
        tag: resolvedTag
    )
}

private func akamaiCloudUnderscored(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "_."))
    return "_\(trimmed)"
}

private func akamaiCloudUnprefixed(_ value: String?) -> String? {
    value?.trimmingCharacters(in: CharacterSet(charactersIn: "_."))
}

private func akamaiCloudDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: value) { return date }

    let fallback = DateFormatter()
    fallback.locale = Locale(identifier: "en_US_POSIX")
    fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return fallback.date(from: value)
}
