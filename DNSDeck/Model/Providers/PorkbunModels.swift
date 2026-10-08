import Foundation

struct PorkbunFlexibleInt: Codable, Hashable, Sendable {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(String.self), let parsed = Int(value) {
            self.value = parsed
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected an integer or integer string"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct PorkbunFlexibleString: Codable, Hashable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int64.self) {
            self.value = String(value)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a string or integer"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct PorkbunStatusEnvelope: Decodable {
    struct NextAction: Decodable {
        let type: String?
        let hint: String?
        let url: String?
    }

    let status: String
    let message: String?
    let code: String?
    let requestId: String?
    let nextAction: NextAction?

    enum CodingKeys: String, CodingKey {
        case status, message, code, requestId
        case nextAction = "next_action"
    }

    var resolvedMessage: String? {
        let primary = message ?? code
        guard let hint = nextAction?.hint else { return primary }
        let action = nextAction?.url.map { "\(hint) (\($0))" } ?? hint
        return primary.map { "\($0)\n\(action)" } ?? action
    }
}

struct PorkbunDomain: Codable, Hashable, Sendable {
    let domain: String
    let status: String?
    let tld: String?
    let createDate: String?
    let expireDate: String?
    let securityLock: PorkbunFlexibleInt?
    let whoisPrivacy: PorkbunFlexibleInt?
    let autoRenew: PorkbunFlexibleInt?
    let apiAccess: PorkbunFlexibleInt?
    let notLocal: PorkbunFlexibleInt?

    func snapshot(nameservers: [String] = []) -> ProviderZoneSnapshot {
        var metadata: [String: String] = [:]
        if let tld { metadata["tld"] = tld }
        if let expireDate { metadata["expireDate"] = expireDate }
        if let securityLock { metadata["securityLock"] = String(securityLock.value) }
        if let whoisPrivacy { metadata["whoisPrivacy"] = String(whoisPrivacy.value) }
        if let autoRenew { metadata["autoRenew"] = String(autoRenew.value) }
        if let apiAccess { metadata["apiAccess"] = String(apiAccess.value) }
        if let notLocal { metadata["notLocal"] = String(notLocal.value) }
        return ProviderZoneSnapshot(
            id: domain,
            name: domain,
            nameservers: nameservers,
            status: status,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct PorkbunDomainListResponse: Decodable {
    let status: String
    let count: Int?
    let domains: [PorkbunDomain]
}

struct PorkbunDomainResponse: Decodable {
    let status: String
    let domain: PorkbunDomain
}

struct PorkbunNameserverResponse: Decodable {
    let status: String
    let ns: [String]
}

struct PorkbunDNSRecord: Codable, Hashable {
    let id: String
    let name: String
    let type: String
    let content: String
    let ttl: PorkbunFlexibleInt?
    let prio: PorkbunFlexibleInt?
    let notes: String?

    func snapshot() -> ProviderRecordSnapshot {
        ProviderRecordSnapshot(
            id: id,
            name: name,
            type: type,
            values: [content],
            ttl: ttl?.value,
            priority: (type.uppercased() == "MX" || type.uppercased() == "SRV") ? prio?.value : nil,
            comment: notes,
            metadata: [:],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct PorkbunDNSRecordsResponse: Decodable {
    let status: String
    let cloudflare: String?
    let records: [PorkbunDNSRecord]
}

struct PorkbunDNSWriteRequest: Codable, Equatable {
    let apiKey: String?
    let secretApiKey: String?
    let name: String
    let type: String
    let content: String
    let ttl: Int?
    let prio: Int?
    let notes: String?
    let dryRun: Bool?

    enum CodingKeys: String, CodingKey {
        case name, type, content, ttl, prio, notes, dryRun
        case apiKey = "apikey"
        case secretApiKey = "secretapikey"
    }

    func authenticated(apiKey: String, secretApiKey: String) -> PorkbunDNSWriteRequest {
        PorkbunDNSWriteRequest(
            apiKey: apiKey,
            secretApiKey: secretApiKey,
            name: name,
            type: type,
            content: content,
            ttl: ttl,
            prio: prio,
            notes: notes,
            dryRun: dryRun
        )
    }
}

struct PorkbunAuthRequest: Codable, Equatable {
    let apiKey: String
    let secretApiKey: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "apikey"
        case secretApiKey = "secretapikey"
    }
}

struct PorkbunNameserverUpdateRequest: Codable, Equatable {
    let apiKey: String
    let secretApiKey: String
    let nameservers: [String]

    enum CodingKeys: String, CodingKey {
        case apiKey = "apikey"
        case secretApiKey = "secretapikey"
        case nameservers = "ns"
    }
}

struct PorkbunCreateDNSResponse: Decodable {
    let status: String
    let id: PorkbunFlexibleString
}

extension CreateProviderRecordRequest {
    func toPorkbunRequests(zoneName: String) throws -> [PorkbunDNSWriteRequest] {
        let type = type.uppercased()
        try validatePorkbunRecordType(type)
        let name = ProviderDNSName.relativeEmptyCaseInsensitive(name, zoneName: zoneName)
        let values = values ?? [recordData?.flatContent ?? content]
        let ttl = DNSProvider.porkbun.getEffectiveTTL(ttl)
        return try values.map {
            let value = try porkbunValue(
                type: type,
                value: $0,
                priority: priority,
                recordData: recordData
            )
            return PorkbunDNSWriteRequest(
                apiKey: nil,
                secretApiKey: nil,
                name: name,
                type: type,
                content: value.content,
                ttl: ttl,
                prio: value.priority,
                notes: comment,
                dryRun: nil
            )
        }
    }
}

extension UpdateProviderRecordRequest {
    func toPorkbunRequest(zoneName: String, existing: PorkbunDNSRecord) throws -> PorkbunDNSWriteRequest {
        guard values == nil || values?.count == 1 else {
            throw ProviderAPIError.invalidRecordContent(
                provider: .porkbun,
                type: type ?? existing.type,
                message: "individual Porkbun record edits accept exactly one value"
            )
        }
        let type = (type ?? existing.type).uppercased()
        try validatePorkbunRecordType(type)
        let sourceValue = values?.first ?? recordData?.flatContent ?? content ?? existing.content
        let value = try porkbunValue(
            type: type,
            value: sourceValue,
            priority: priority ?? existing.prio?.value,
            recordData: recordData
        )
        return PorkbunDNSWriteRequest(
            apiKey: nil,
            secretApiKey: nil,
            name: ProviderDNSName.relativeEmptyCaseInsensitive(name ?? existing.name, zoneName: zoneName),
            type: type,
            content: value.content,
            ttl: DNSProvider.porkbun.normalizeTTL(ttl ?? existing.ttl?.value),
            prio: value.priority,
            notes: comment ?? existing.notes,
            dryRun: nil
        )
    }
}

private func porkbunValue(
    type: String,
    value: String,
    priority: Int?,
    recordData: RecordData?
) throws -> (content: String, priority: Int?) {
    if type == "MX" {
        let parts = value.split(whereSeparator: \Character.isWhitespace)
        if let embeddedPriority = parts.first.flatMap({ Int($0) }) {
            return (parts.dropFirst().joined(separator: " "), embeddedPriority)
        }
        return (recordData?.target ?? value, recordData?.priority ?? priority ?? 0)
    }

    if type == "SRV" {
        if let recordData,
           let weight = recordData.weight,
           let port = recordData.port,
           let target = recordData.target
        {
            try validatePorkbunSRV(weight: weight, port: port)
            return ("\(weight) \(port) \(target)", recordData.priority ?? priority ?? 0)
        }

        let parts = value.split(whereSeparator: \Character.isWhitespace)
        if parts.count >= 4,
           let embeddedPriority = Int(parts[0]),
           let weight = Int(parts[1]),
           let port = Int(parts[2])
        {
            try validatePorkbunSRV(weight: weight, port: port)
            return ("\(weight) \(port) \(parts.dropFirst(3).joined(separator: " "))", embeddedPriority)
        }
        if parts.count >= 3, let weight = Int(parts[0]), let port = Int(parts[1]) {
            try validatePorkbunSRV(weight: weight, port: port)
            return ("\(weight) \(port) \(parts.dropFirst(2).joined(separator: " "))", priority ?? 0)
        }
        throw ProviderAPIError.invalidRecordContent(
            provider: .porkbun,
            type: type,
            message: "expected priority, weight, port, and target, or a separate priority with weight, port, and target"
        )
    }

    return (value, nil)
}

private func validatePorkbunSRV(weight: Int, port: Int) throws {
    guard (0 ... 65535).contains(weight), (1 ... 65535).contains(port) else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .porkbun,
            type: "SRV",
            message: "weight must be 0 through 65535 and port must be 1 through 65535"
        )
    }
}

private func validatePorkbunRecordType(_ type: String) throws {
    guard DNSProvider.porkbun.capabilities.canEdit(recordType: type) else {
        throw ProviderAPIError.invalidRecordContent(
            provider: .porkbun,
            type: type,
            message: "the record type is provider-managed or unsupported by Porkbun API v3"
        )
    }
}
