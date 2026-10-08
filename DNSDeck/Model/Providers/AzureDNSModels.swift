import Foundation

struct AzureDNSAccessTokenResponse: Decodable, Equatable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

struct AzureDNSZoneListResponse: Decodable, Equatable {
    let value: [AzureDNSZone]
    let nextLink: String?
}

struct AzureDNSZone: Codable, Hashable {
    let id: String
    let name: String
    let type: String?
    let location: String?
    let tags: [String: String]?
    let etag: String?
    let properties: AzureDNSZoneProperties?

    var resourceGroup: String? {
        let components = id.split(separator: "/").map(String.init)
        guard let index = components.firstIndex(where: {
            $0.caseInsensitiveCompare("resourceGroups") == .orderedSame
        }), components.indices.contains(index + 1)
        else {
            return nil
        }
        return components[index + 1]
    }

    var isPublic: Bool {
        guard let zoneType = properties?.zoneType else { return true }
        return zoneType.caseInsensitiveCompare("Public") == .orderedSame
    }

    func snapshot() -> ProviderZoneSnapshot {
        var metadata: [String: String] = [:]
        if let resourceGroup { metadata["resourceGroup"] = resourceGroup }
        if let location { metadata["location"] = location }
        if let zoneType = properties?.zoneType { metadata["zoneType"] = zoneType }
        if let count = properties?.numberOfRecordSets { metadata["recordSetCount"] = String(count) }
        for (key, value) in tags ?? [:] {
            metadata["tag.\(key)"] = value
        }

        return ProviderZoneSnapshot(
            id: id,
            name: name.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            nameservers: properties?.nameServers ?? [],
            status: properties?.zoneType,
            etag: etag,
            metadata: metadata,
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct AzureDNSZoneProperties: Codable, Hashable {
    let maxNumberOfRecordSets: Int?
    let maxNumberOfRecordsPerRecordSet: Int?
    let numberOfRecordSets: Int?
    let nameServers: [String]?
    let zoneType: String?
}

struct AzureDNSZoneWriteRequest: Encodable, Equatable {
    let location: String
}

struct AzureDNSRecordSetListResponse: Decodable, Equatable {
    let value: [AzureDNSRecordSet]
    let nextLink: String?
}

struct AzureDNSRecordSet: Codable, Hashable {
    let id: String
    let name: String
    let type: String
    let etag: String?
    let properties: AzureDNSRecordSetProperties

    var recordType: String {
        type.split(separator: "/").last.map(String.init)?.uppercased() ?? type.uppercased()
    }

    func snapshot(zoneName: String) -> ProviderRecordSnapshot {
        let type = recordType
        let values = properties.values(for: type)
        let displayName = (properties.fqdn ?? azureDNSAbsoluteName(name, zoneName: zoneName))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let alias = properties.targetResource?.id.map {
            DNSAliasTarget(name: $0, zoneId: nil, evaluateTargetHealth: nil)
        }

        return ProviderRecordSnapshot(
            id: id,
            name: displayName,
            type: type,
            values: alias.map { [$0.name] } ?? values,
            ttl: properties.ttl,
            priority: properties.priority(for: type),
            aliasTarget: alias,
            etag: etag,
            metadata: properties.metadata ?? [:],
            providerData: try? JSONEncoder().encode(self)
        )
    }
}

struct AzureDNSRecordSetProperties: Codable, Hashable {
    var metadata: [String: String]? = nil
    var ttl: Int? = nil
    var fqdn: String? = nil
    var provisioningState: String? = nil
    var targetResource: AzureDNSSubResource? = nil
    var aRecords: [AzureDNSARecord]? = nil
    var aaaaRecords: [AzureDNSAAAARecord]? = nil
    var mxRecords: [AzureDNSMXRecord]? = nil
    var nsRecords: [AzureDNSNSRecord]? = nil
    var ptrRecords: [AzureDNSPTRRecord]? = nil
    var srvRecords: [AzureDNSSRVRecord]? = nil
    var txtRecords: [AzureDNSTXTRecord]? = nil
    var cnameRecord: AzureDNSCNAMERecord? = nil
    var soaRecord: AzureDNSSOARecord? = nil
    var caaRecords: [AzureDNSCAARecord]? = nil

    enum CodingKeys: String, CodingKey {
        case metadata
        case ttl = "TTL"
        case fqdn
        case provisioningState
        case targetResource
        case aRecords = "ARecords"
        case aaaaRecords = "AAAARecords"
        case mxRecords = "MXRecords"
        case nsRecords = "NSRecords"
        case ptrRecords = "PTRRecords"
        case srvRecords = "SRVRecords"
        case txtRecords = "TXTRecords"
        case cnameRecord = "CNAMERecord"
        case soaRecord = "SOARecord"
        case caaRecords
    }

    func values(for type: String) -> [String] {
        switch type.uppercased() {
        case "A":
            return aRecords?.compactMap(\.ipv4Address) ?? []
        case "AAAA":
            return aaaaRecords?.compactMap(\.ipv6Address) ?? []
        case "CAA":
            guard let caaRecords else { return [] }
            return caaRecords.compactMap { record in
                guard let flags = record.flags, let tag = record.tag, let value = record.value else { return nil }
                return "\(flags) \(tag) \(value)"
            }
        case "CNAME":
            guard let cname = cnameRecord?.cname else { return [] }
            return [cname]
        case "MX":
            guard let mxRecords else { return [] }
            return mxRecords.compactMap { record in
                guard let preference = record.preference, let exchange = record.exchange else { return nil }
                return "\(preference) \(exchange)"
            }
        case "NS":
            return nsRecords?.compactMap(\.nsdname) ?? []
        case "PTR":
            return ptrRecords?.compactMap(\.ptrdname) ?? []
        case "SRV":
            guard let srvRecords else { return [] }
            return srvRecords.compactMap { record in
                guard let priority = record.priority,
                      let weight = record.weight,
                      let port = record.port,
                      let target = record.target
                else {
                    return nil
                }
                return "\(priority) \(weight) \(port) \(target)"
            }
        case "TXT":
            return txtRecords?.map { $0.value?.joined() ?? "" } ?? []
        case "SOA":
            guard let soaRecord else { return [] }
            let host: String = soaRecord.host ?? ""
            let email: String = soaRecord.email ?? ""
            let serialNumber = String(soaRecord.serialNumber ?? 0)
            let refreshTime = String(soaRecord.refreshTime ?? 0)
            let retryTime = String(soaRecord.retryTime ?? 0)
            let expireTime = String(soaRecord.expireTime ?? 0)
            let minimumTTL = String(soaRecord.minimumTTL ?? 0)
            return [
                "\(host) \(email) \(serialNumber) \(refreshTime) \(retryTime) \(expireTime) \(minimumTTL)",
            ]
        default:
            return []
        }
    }

    func priority(for type: String) -> Int? {
        switch type.uppercased() {
        case "MX": mxRecords?.count == 1 ? mxRecords?.first?.preference : nil
        case "SRV": srvRecords?.count == 1 ? srvRecords?.first?.priority : nil
        default: nil
        }
    }

    func writable(ttl: Int? = nil) -> AzureDNSRecordSetProperties {
        AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl ?? self.ttl,
            targetResource: targetResource,
            aRecords: aRecords,
            aaaaRecords: aaaaRecords,
            mxRecords: mxRecords,
            nsRecords: nsRecords,
            ptrRecords: ptrRecords,
            srvRecords: srvRecords,
            txtRecords: txtRecords,
            cnameRecord: cnameRecord,
            soaRecord: soaRecord,
            caaRecords: caaRecords
        )
    }
}

struct AzureDNSRecordSetWriteRequest: Encodable, Equatable {
    let properties: AzureDNSRecordSetProperties
}

struct AzureDNSSubResource: Codable, Hashable {
    let id: String?
}

struct AzureDNSARecord: Codable, Hashable {
    let ipv4Address: String?
}

struct AzureDNSAAAARecord: Codable, Hashable {
    let ipv6Address: String?
}

struct AzureDNSCNAMERecord: Codable, Hashable {
    let cname: String?
}

struct AzureDNSMXRecord: Codable, Hashable {
    let preference: Int?
    let exchange: String?
}

struct AzureDNSNSRecord: Codable, Hashable {
    let nsdname: String?
}

struct AzureDNSPTRRecord: Codable, Hashable {
    let ptrdname: String?
}

struct AzureDNSSRVRecord: Codable, Hashable {
    let priority: Int?
    let weight: Int?
    let port: Int?
    let target: String?
}

struct AzureDNSTXTRecord: Codable, Hashable {
    let value: [String]?
}

struct AzureDNSCAARecord: Codable, Hashable {
    let flags: Int?
    let tag: String?
    let value: String?
}

struct AzureDNSSOARecord: Codable, Hashable {
    let host: String?
    let email: String?
    let serialNumber: Int?
    let refreshTime: Int?
    let retryTime: Int?
    let expireTime: Int?
    let minimumTTL: Int?
}

struct AzureDNSRecordMutation: Equatable {
    let relativeName: String
    let type: String
    let request: AzureDNSRecordSetWriteRequest
}

struct AzureDNSOperationStatus: Decodable, Equatable {
    struct OperationError: Decodable, Equatable {
        let code: String?
        let message: String?
    }

    let status: String
    let error: OperationError?
}

extension CreateProviderRecordRequest {
    func toAzureDNSMutation(zoneName: String) throws -> AzureDNSRecordMutation {
        let type = type.uppercased()
        try validateAzureDNSRecordType(type)
        let resolvedValues = values ?? [recordData?.flatContent ?? content]
        let properties = try azureDNSProperties(
            type: type,
            values: resolvedValues,
            ttl: DNSProvider.azureDNS.getEffectiveTTL(ttl) ?? DNSProvider.azureDNS.defaultTTL,
            priority: priority,
            recordData: recordData,
            metadata: nil,
            aliasTarget: aliasTarget
        )
        return AzureDNSRecordMutation(
            relativeName: ProviderDNSName.relativeAtCaseInsensitive(name, zoneName: zoneName),
            type: type,
            request: AzureDNSRecordSetWriteRequest(properties: properties)
        )
    }
}

extension UpdateProviderRecordRequest {
    func toAzureDNSMutation(zoneName: String, existing: AzureDNSRecordSet) throws -> AzureDNSRecordMutation {
        let type = (type ?? existing.recordType).uppercased()
        try validateAzureDNSRecordType(type)
        let changesRecordData = values != nil || content != nil || recordData != nil || aliasTarget != nil ||
            type.caseInsensitiveCompare(existing.recordType) != .orderedSame
        let properties: AzureDNSRecordSetProperties

        if changesRecordData {
            let resolvedValues = values ?? content.map { [$0] } ?? recordData?.flatContent.map { [$0] } ??
                existing.properties.values(for: existing.recordType)
            let requestedAlias = aliasTarget ?? (["A", "AAAA", "CNAME"].contains(type) ?
                resolvedValues.first.flatMap {
                    $0.lowercased().hasPrefix("/subscriptions/") ? $0 : nil
                } : nil)
            properties = try azureDNSProperties(
                type: type,
                values: resolvedValues,
                ttl: DNSProvider.azureDNS.normalizeTTL(ttl ?? existing.properties.ttl) ??
                    DNSProvider.azureDNS.defaultTTL,
                priority: priority ?? existing.properties.priority(for: existing.recordType),
                recordData: recordData,
                metadata: existing.properties.metadata,
                aliasTarget: requestedAlias
            )
        } else {
            properties = existing.properties.writable(
                ttl: DNSProvider.azureDNS.normalizeTTL(ttl ?? existing.properties.ttl) ??
                    DNSProvider.azureDNS.defaultTTL
            )
        }

        return AzureDNSRecordMutation(
            relativeName: ProviderDNSName.relativeAtCaseInsensitive(name ?? existing.name, zoneName: zoneName),
            type: type,
            request: AzureDNSRecordSetWriteRequest(properties: properties)
        )
    }
}

private func azureDNSProperties(
    type: String,
    values: [String],
    ttl: Int,
    priority: Int?,
    recordData: RecordData?,
    metadata: [String: String]?,
    aliasTarget: String?
) throws -> AzureDNSRecordSetProperties {
    if let aliasTarget {
        guard ["A", "AAAA", "CNAME"].contains(type) else {
            throw azureDNSInvalid(type, "alias targets are supported only for A, AAAA, and CNAME RRsets")
        }
        guard aliasTarget.lowercased().hasPrefix("/subscriptions/") else {
            throw azureDNSInvalid(type, "an alias target must be a complete Azure resource ID")
        }
        return AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl,
            targetResource: AzureDNSSubResource(id: aliasTarget)
        )
    }

    switch type {
    case "A":
        return AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl,
            aRecords: values.map { AzureDNSARecord(ipv4Address: $0) }
        )
    case "AAAA":
        return AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl,
            aaaaRecords: values.map { AzureDNSAAAARecord(ipv6Address: $0) }
        )
    case "CAA":
        return try AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl,
            caaRecords: values.map { value in
                let parts = value.split(maxSplits: 2, whereSeparator: \Character.isWhitespace)
                let flags = recordData?.flags ?? parts.first.flatMap { Int($0) }
                let tag = recordData?.tag ?? (parts.count > 1 ? String(parts[1]) : nil)
                let target = recordData?.value ?? (parts.count > 2 ? String(parts[2]) : nil)
                guard let flags, (0 ... 255).contains(flags), let tag, let target else {
                    throw azureDNSInvalid(type, "expected flags (0 through 255), tag, and value")
                }
                return AzureDNSCAARecord(flags: flags, tag: tag, value: target.trimmingQuotes)
            }
        )
    case "CNAME":
        guard values.count == 1, let value = values.first else {
            throw azureDNSInvalid(type, "CNAME RRsets must contain exactly one value")
        }
        return AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl,
            cnameRecord: AzureDNSCNAMERecord(cname: value)
        )
    case "MX":
        return try AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl,
            mxRecords: values.map { value in
                let parts = value.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
                let embeddedPriority = parts.first.flatMap { Int($0) }
                let resolvedPriority = embeddedPriority ?? recordData?.priority ?? priority
                let exchange: String
                if embeddedPriority != nil {
                    guard parts.count == 2 else {
                        throw azureDNSInvalid(type, "expected a preference and an exchange")
                    }
                    exchange = String(parts[1])
                } else {
                    exchange = recordData?.target ?? value
                }
                guard let resolvedPriority, (0 ... 65535).contains(resolvedPriority), !exchange.isEmpty else {
                    throw azureDNSInvalid(type, "expected a preference from 0 through 65535 and an exchange")
                }
                return AzureDNSMXRecord(preference: resolvedPriority, exchange: exchange)
            }
        )
    case "NS":
        return AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl,
            nsRecords: values.map { AzureDNSNSRecord(nsdname: $0) }
        )
    case "PTR":
        return AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl,
            ptrRecords: values.map { AzureDNSPTRRecord(ptrdname: $0) }
        )
    case "SRV":
        return try AzureDNSRecordSetProperties(
            metadata: metadata,
            ttl: ttl,
            srvRecords: values.map { value in
                if let recordData,
                   let weight = recordData.weight,
                   let port = recordData.port,
                   let target = recordData.target
                {
                    return try azureDNSSRV(
                        priority: recordData.priority ?? priority ?? 0,
                        weight: weight,
                        port: port,
                        target: target
                    )
                }
                let parts = value.split(maxSplits: 3, whereSeparator: \Character.isWhitespace)
                guard parts.count == 4,
                      let priority = Int(parts[0]),
                      let weight = Int(parts[1]),
                      let port = Int(parts[2])
                else {
                    throw azureDNSInvalid(type, "expected priority, weight, port, and target")
                }
                return try azureDNSSRV(
                    priority: priority,
                    weight: weight,
                    port: port,
                    target: String(parts[3])
                )
            }
        )
    case "TXT":
        let records = values.compactMap { value -> AzureDNSTXTRecord? in
            value.isEmpty ? nil : AzureDNSTXTRecord(value: azureDNSSplitTXT(value))
        }
        return AzureDNSRecordSetProperties(metadata: metadata, ttl: ttl, txtRecords: records)
    default:
        throw azureDNSInvalid(type, "the record type is provider-managed or unsupported by Azure DNS")
    }
}

private func azureDNSSRV(priority: Int, weight: Int, port: Int, target: String) throws -> AzureDNSSRVRecord {
    guard (0 ... 65535).contains(priority),
          (0 ... 65535).contains(weight),
          (0 ... 65535).contains(port),
          !target.isEmpty
    else {
        throw azureDNSInvalid("SRV", "priority, weight, and port must be 0 through 65535")
    }
    return AzureDNSSRVRecord(priority: priority, weight: weight, port: port, target: target)
}

private func validateAzureDNSRecordType(_ type: String) throws {
    guard DNSProvider.azureDNS.capabilities.canEdit(recordType: type) else {
        throw azureDNSInvalid(type, "the record type is provider-managed or unsupported by Azure DNS")
    }
}

private func azureDNSInvalid(_ type: String, _ message: String) -> ProviderAPIError {
    ProviderAPIError.invalidRecordContent(provider: .azureDNS, type: type, message: message)
}

private func azureDNSAbsoluteName(_ relativeName: String, zoneName: String) -> String {
    relativeName == "@" ? zoneName : "\(relativeName).\(zoneName)"
}

private func azureDNSSplitTXT(_ value: String) -> [String] {
    var chunks: [String] = []
    var current = ""
    var currentByteCount = 0

    for character in value {
        let fragment = String(character)
        let fragmentByteCount = fragment.utf8.count
        if currentByteCount + fragmentByteCount > 255, !current.isEmpty {
            chunks.append(current)
            current = ""
            currentByteCount = 0
        }
        current.append(character)
        currentByteCount += fragmentByteCount
    }
    if !current.isEmpty || chunks.isEmpty { chunks.append(current) }
    return chunks
}

private extension String {
    var trimmingQuotes: String {
        guard hasPrefix("\""), hasSuffix("\""), count >= 2 else { return self }
        return String(dropFirst().dropLast())
    }
}
