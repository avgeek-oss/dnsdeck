

import Foundation

/// Cloudflare Envelope
struct CFEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let result: T?
    let errors: [CFError]
    let messages: [CFMessage]?
    let result_info: CFResultInfo?
}

struct CFError: Decodable, Error {
    let code: Int
    let message: String
}

struct CFMessage: Decodable {
    let code: Int?
    let message: String?
}

struct CFResultInfo: Decodable {
    let page: Int?
    let per_page: Int?
    let total_pages: Int?
    let count: Int?
    let total_count: Int?
}

/// Zones
struct CFZone: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String?
    let account: CFZoneAccount?
    let name_servers: [String]?
}

struct CFZoneAccount: Codable, Hashable {
    let id: String?
    let name: String?
}

extension CFZone {
    func snapshot() -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: id,
            name: name,
            nameservers: name_servers ?? [],
            status: status,
            metadata: account.map { ["account": $0.name ?? $0.id ?? ""] } ?? [:],
            providerData: providerSnapshotData
        )
    }
}

struct CFCreateZoneRequest: Encodable {
    let account: CFCreateZoneAccount
    let name: String
    let type: String
}

struct CFCreateZoneAccount: Encodable {
    let id: String?
}

/// DNS Records
struct CFDNSRecord: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let content: String
    let ttl: Int?
    let proxied: Bool?
    let proxiable: Bool?
    let priority: Int?
    let tags: [String]?
    let data: RecordData?
    let created_on: Date?
    let modified_on: Date?
    let meta: CFRecordMeta?
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, content, ttl, proxied, proxiable, priority, tags, data
        case created_on, modified_on, meta, comment
    }

    /// Custom initializer to handle missing timestamp fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        content = try container.decode(String.self, forKey: .content)

        // Optional fields
        ttl = try container.decodeIfPresent(Int.self, forKey: .ttl)
        proxied = try container.decodeIfPresent(Bool.self, forKey: .proxied)
        proxiable = try container.decodeIfPresent(Bool.self, forKey: .proxiable)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        // Cloudflare's `data` shape varies by record type. RecordData covers
        // the shared SRV/CAA representation; flat `content` remains canonical
        // when a provider-specific data shape cannot be decoded.
        data = try? container.decodeIfPresent(RecordData.self, forKey: .data)
        meta = try container.decodeIfPresent(CFRecordMeta.self, forKey: .meta)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)

        // Timestamp fields - handle Cloudflare's ISO8601 format with fractional seconds
        if let createdString = try? container.decodeIfPresent(String.self, forKey: .created_on) {
            created_on = ProviderRecordValue.date(createdString)
        } else {
            created_on = nil
        }

        if let modifiedString = try? container.decodeIfPresent(String.self, forKey: .modified_on) {
            modified_on = ProviderRecordValue.date(modifiedString)
        } else {
            modified_on = nil
        }
    }
}

extension CFDNSRecord {
    func snapshot() -> ProviderRecordSnapshot {
        ProviderRecordSnapshot(
            id: id,
            name: name,
            type: type,
            values: [data?.flatContent ?? content],
            displayContent: content,
            ttl: ttl,
            proxied: proxied,
            priority: priority,
            comment: comment,
            createdOn: created_on,
            modifiedOn: modified_on,
            providerData: providerSnapshotData
        )
    }
}

/// Create / Update payloads
struct CreateDNSRecordRequest: Encodable {
    var type: String
    var name: String
    var content: String?
    var ttl: Int? // 1 = automatic
    var proxied: Bool?
    var priority: Int?
    var data: CloudflareRecordData?
    var comment: String?
}

struct UpdateDNSRecordRequest: Encodable {
    var type: String?
    var name: String?
    var content: String?
    var ttl: Int?
    var proxied: Bool?
    var priority: Int?
    var data: CloudflareRecordData?
    var comment: String?
}

enum CloudflareRecordData: Encodable {
    case components(RecordData)
    case ds(keyTag: Int, algorithm: Int, digestType: Int, digest: String)
    case serviceBinding(priority: Int, target: String, value: String)
    case naptr(order: Int, preference: Int, flags: String, service: String, regex: String, replacement: String)
    case sshfp(algorithm: Int, fingerprintType: Int, fingerprint: String)
    case tlsa(usage: Int, selector: Int, matchingType: Int, certificate: String)

    private enum CodingKeys: String, CodingKey {
        case algorithm, certificate, digest, fingerprint, flags, order, preference
        case priority, regex, replacement, selector, service, target, value, usage
        case digestType = "digest_type"
        case fingerprintType = "type"
        case keyTag = "key_tag"
        case matchingType = "matching_type"
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .components(data):
            try data.encode(to: encoder)
        case let .ds(keyTag, algorithm, digestType, digest):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(keyTag, forKey: .keyTag)
            try container.encode(algorithm, forKey: .algorithm)
            try container.encode(digestType, forKey: .digestType)
            try container.encode(digest, forKey: .digest)
        case let .serviceBinding(priority, target, value):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(priority, forKey: .priority)
            try container.encode(target, forKey: .target)
            try container.encode(value, forKey: .value)
        case let .naptr(order, preference, flags, service, regex, replacement):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(order, forKey: .order)
            try container.encode(preference, forKey: .preference)
            try container.encode(flags, forKey: .flags)
            try container.encode(service, forKey: .service)
            try container.encode(regex, forKey: .regex)
            try container.encode(replacement, forKey: .replacement)
        case let .sshfp(algorithm, fingerprintType, fingerprint):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(algorithm, forKey: .algorithm)
            try container.encode(fingerprintType, forKey: .fingerprintType)
            try container.encode(fingerprint, forKey: .fingerprint)
        case let .tlsa(usage, selector, matchingType, certificate):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(usage, forKey: .usage)
            try container.encode(selector, forKey: .selector)
            try container.encode(matchingType, forKey: .matchingType)
            try container.encode(certificate, forKey: .certificate)
        }
    }

    static func parse(type: String, content: String) -> CloudflareRecordData? {
        let fields = presentationFields(content)

        switch type.uppercased() {
        case "DS":
            guard fields.count == 4,
                  let keyTag = Int(fields[0]),
                  let algorithm = Int(fields[1]),
                  let digestType = Int(fields[2])
            else { return nil }
            return .ds(
                keyTag: keyTag,
                algorithm: algorithm,
                digestType: digestType,
                digest: fields[3]
            )
        case "HTTPS", "SVCB":
            let components = content.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard components.count >= 2, let priority = Int(components[0]) else { return nil }
            return .serviceBinding(
                priority: priority,
                target: String(components[1]),
                value: components.count == 3 ? String(components[2]) : ""
            )
        case "NAPTR":
            guard fields.count == 6,
                  let order = Int(fields[0]),
                  let preference = Int(fields[1])
            else { return nil }
            return .naptr(
                order: order,
                preference: preference,
                flags: fields[2],
                service: fields[3],
                regex: fields[4],
                replacement: fields[5]
            )
        case "SSHFP":
            guard fields.count == 3,
                  let algorithm = Int(fields[0]),
                  let fingerprintType = Int(fields[1])
            else { return nil }
            return .sshfp(
                algorithm: algorithm,
                fingerprintType: fingerprintType,
                fingerprint: fields[2]
            )
        case "TLSA":
            guard fields.count == 4,
                  let usage = Int(fields[0]),
                  let selector = Int(fields[1]),
                  let matchingType = Int(fields[2])
            else { return nil }
            return .tlsa(
                usage: usage,
                selector: selector,
                matchingType: matchingType,
                certificate: fields[3]
            )
        default:
            return nil
        }
    }

    private static func presentationFields(_ value: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var escaping = false

        for character in value {
            if escaping {
                field.append(character)
                escaping = false
            } else if character == "\\" {
                field.append(character)
                escaping = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character.isWhitespace, !quoted {
                if !field.isEmpty {
                    fields.append(field)
                    field = ""
                }
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty { fields.append(field) }
        return fields
    }
}

struct RecordData: Codable, Hashable {
    var service: String?
    var proto: String?
    var name: String?
    var priority: Int?
    var weight: Int?
    var port: Int?
    var target: String?
    var flags: Int?
    var tag: String?
    var value: String?

    var isSRV: Bool {
        service != nil
    }

    var isCAA: Bool {
        tag != nil
    }

    var flatContent: String? {
        if isSRV {
            return "\(priority ?? 0) \(weight ?? 0) \(port ?? 0) \(target ?? "")"
        }
        if isCAA {
            return "\(flags ?? 0) \(tag ?? "") \(value ?? "")"
        }
        return nil
    }
}

struct CFRecordMeta: Codable, Hashable {
    let source: String?
}

// Helper function to parse Cloudflare's timestamp format
