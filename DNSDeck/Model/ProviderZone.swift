
import Foundation

private func route53Values(
    _ values: [String],
    type: String,
    priority: Int? = nil,
    recordData: RecordData? = nil,
    existingValues: [String] = []
) -> [String] {
    values.enumerated().map { index, value in
        let existingPriority = existingValues.indices.contains(index)
            ? ProviderRecordValue.priority(existingValues[index])
            : nil
        return route53Value(
            value,
            type: type,
            priority: priority ?? existingPriority,
            recordData: recordData
        )
    }
}

private func route53Value(
    _ value: String,
    type: String,
    priority: Int? = nil,
    recordData: RecordData? = nil
) -> String {
    switch type.uppercased() {
    case "CAA":
        guard let data = UpdateProviderRecordRequest.cloudflareCAAData(content: value),
              let flags = data.flags,
              let tag = data.tag,
              let caaValue = data.value
        else { return value }
        return "\(flags) \(tag) \(ProviderRecordValue.quotedTXT(caaValue))"
    case "MX":
        guard ProviderRecordValue.priority(value) == nil else { return value }
        return "\(recordData?.priority ?? priority ?? 10) \(recordData?.target ?? value)"
    case "TXT":
        return ProviderRecordValue.quotedTXT(value, maximumChunkBytes: 255)
    default:
        return value
    }
}

private func googleCloudValues(
    _ values: [String],
    type: String,
    priority: Int? = nil,
    recordData: RecordData? = nil,
    existingValues: [String] = []
) -> [String] {
    values.enumerated().map { index, value in
        let existingPriority = existingValues.indices.contains(index)
            ? ProviderRecordValue.priority(existingValues[index])
            : nil
        let rendered = route53Value(
            value,
            type: type,
            priority: priority ?? existingPriority,
            recordData: recordData
        )

        switch type.uppercased() {
        case "CNAME", "NS", "PTR":
            return googleCloudAbsoluteTarget(rendered)
        case "MX":
            let parts = rendered.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return rendered }
            return "\(parts[0]) \(googleCloudAbsoluteTarget(parts[1]))"
        case "SRV":
            let parts = rendered.split(separator: " ", maxSplits: 3).map(String.init)
            guard parts.count == 4 else { return rendered }
            return "\(parts[0]) \(parts[1]) \(parts[2]) \(googleCloudAbsoluteTarget(parts[3]))"
        case "HTTPS", "SVCB":
            let parts = rendered.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count >= 2 else { return rendered }
            let parameters = parts.count == 3 ? " \(parts[2])" : ""
            return "\(parts[0]) \(googleCloudAbsoluteTarget(parts[1]))\(parameters)"
        default:
            return rendered
        }
    }
}

private func googleCloudAbsoluteTarget(_ value: String) -> String {
    let target = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !target.isEmpty, target != ".", !target.hasSuffix(".") else { return target }
    return "\(target)."
}

protocol ProviderSnapshotData: Hashable {
    var providerData: Data? { get }
}

extension ProviderSnapshotData {
    init(snapshot: Self) {
        self = snapshot
    }

    var snapshot: Self {
        self
    }

    func decode<T: Decodable>(_ type: T.Type = T.self) -> T? {
        providerData.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

extension ProviderZoneSnapshot: ProviderSnapshotData {}
extension ProviderRecordSnapshot: ProviderSnapshotData {}

typealias ProviderZoneData = ProviderZoneSnapshot
typealias ProviderRecordData = ProviderRecordSnapshot

@dynamicMemberLookup
struct ProviderZone: Identifiable, Hashable {
    let provider: DNSProvider
    let zoneData: ProviderZoneData
    let environmentId: UUID

    var id: String {
        "\(provider.rawValue)|\(zoneData.id)"
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<ProviderZoneSnapshot, Value>) -> Value {
        zoneData[keyPath: keyPath]
    }

    init(provider: DNSProvider, snapshot: ProviderZoneSnapshot, environmentId: UUID) {
        self.provider = provider
        self.environmentId = environmentId
        zoneData = snapshot
    }
}

@dynamicMemberLookup
struct ProviderRecord: Identifiable, Hashable {
    let provider: DNSProvider
    let recordData: ProviderRecordData

    var id: String {
        "\(provider.rawValue)|\(recordData.id)"
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<ProviderRecordSnapshot, Value>) -> Value {
        recordData[keyPath: keyPath]
    }

    var isEditable: Bool {
        if recordData.snapshot.metadata["isProtected"] == "true" {
            return false
        }
        return provider.capabilities.canEdit(recordType: recordData.type)
    }

    init(provider: DNSProvider, snapshot: ProviderRecordSnapshot) {
        self.provider = provider
        recordData = snapshot
    }
}

struct CreateProviderRecordRequest {
    let name: String
    let type: String
    let content: String
    let ttl: Int?
    let proxied: Bool?
    let priority: Int?
    let comment: String?
    var recordData: RecordData?
    var values: [String]?
    var aliasTarget: String?

    func toCloudflareRequest(zoneName: String) -> CreateDNSRecordRequest {
        let data = UpdateProviderRecordRequest.cloudflareData(
            zoneName: zoneName,
            type: type,
            name: name,
            content: content,
            priority: priority,
            recordData: recordData
        )

        return CreateDNSRecordRequest(
            type: type,
            name: name,
            content: data != nil ? nil : content,
            ttl: ttl,
            proxied: proxied,
            priority: data != nil ? nil : priority,
            data: data,
            comment: comment
        )
    }

    func toRoute53Request() -> CreateR53RecordRequest {
        let r53TTL = ttl ?? 300

        return CreateR53RecordRequest(
            name: name,
            type: type,
            ttl: r53TTL,
            values: route53Values(
                [content],
                type: type,
                priority: priority,
                recordData: recordData
            ),
            weight: nil,
            setIdentifier: nil
        )
    }

    func toRoute53Request(zoneName: String) -> CreateR53RecordRequest {
        let rawValues = values ?? recordData?.flatContent.map { [$0] } ?? [content]
        return CreateR53RecordRequest(
            name: ProviderDNSName.absolute(name, in: zoneName, trailingDot: true),
            type: type,
            ttl: ttl ?? 300,
            values: route53Values(
                rawValues,
                type: type,
                priority: priority,
                recordData: recordData
            ),
            weight: nil,
            setIdentifier: nil
        )
    }

    func toVercelRequest(domain: String) -> CreateVercelDNSRecordRequest {
        CreateVercelDNSRecordRequest(
            type: type,
            name: ProviderDNSName.relativeEmptyCaseInsensitive(name, zoneName: domain),
            value: recordData?.flatContent ?? content,
            ttl: DNSProvider.vercel.normalizeTTL(ttl),
            comment: comment,
            mxPriority: priority
        )
    }

    func toGoogleCloudRequest(zoneName: String) -> GCPResourceRecordSet {
        let rawContent: [String] = if let values {
            values
        } else if let recordData, let flat = recordData.flatContent {
            [flat]
        } else if type == "MX", let priority {
            ["\(priority) \(content)"]
        } else {
            [content]
        }
        let gcpContent = googleCloudValues(
            rawContent,
            type: type,
            priority: priority,
            recordData: recordData
        )

        return GCPResourceRecordSet(
            name: ProviderDNSName.absolute(name, in: zoneName, trailingDot: true),
            type: type,
            ttl: ttl ?? DNSProvider.googleCloud.defaultTTL,
            rrdatas: gcpContent
        )
    }
}

struct UpdateProviderRecordRequest {
    var name: String?
    var type: String?
    var content: String?
    var ttl: Int?
    var proxied: Bool?
    var priority: Int?
    var comment: String?
    var values: [String]?
    var aliasTarget: String?
    var recordData: RecordData?

    func toCloudflareRequest(zoneName: String, existingRecord: CFDNSRecord? = nil) -> UpdateDNSRecordRequest {
        let resolvedType = type ?? existingRecord?.type
        let resolvedName = name ?? existingRecord?.name
        let resolvedContent = content ?? values?.first ?? existingRecord?.content
        let resolvedTTL = ttl ?? existingRecord?.ttl
        let resolvedProxied = proxied ?? existingRecord?.proxied
        let resolvedPriority = priority ?? existingRecord?.priority
        let resolvedComment = comment ?? existingRecord?.comment
        let resolvedData = resolvedCloudflareData(
            zoneName: zoneName,
            type: resolvedType,
            name: resolvedName,
            content: resolvedContent,
            priority: resolvedPriority,
            existingData: existingRecord?.data
        )

        return UpdateDNSRecordRequest(
            type: resolvedType,
            name: resolvedName,
            content: resolvedData != nil ? nil : resolvedContent,
            ttl: resolvedTTL,
            proxied: resolvedProxied,
            priority: resolvedData != nil ? nil : resolvedPriority,
            data: resolvedData,
            comment: resolvedComment
        )
    }

    func toRoute53Request(oldRecord: R53ResourceRecordSet, zoneName: String) -> UpdateR53RecordRequest {
        buildRoute53Request(
            oldRecord: oldRecord,
            resolvedName: name.map { ProviderDNSName.absolute($0, in: zoneName, trailingDot: true) }
        )
    }

    private func buildRoute53Request(oldRecord: R53ResourceRecordSet, resolvedName: String?) -> UpdateR53RecordRequest {
        let newAliasTarget = aliasTarget.map {
            R53AliasTarget(
                dnsName: $0,
                hostedZoneId: oldRecord.aliasTarget?.hostedZoneId ?? "",
                evaluateTargetHealth: oldRecord.aliasTarget?.evaluateTargetHealth ?? false
            )
        }

        let resolvedValues: [String]? = if let values {
            values
        } else if let content {
            [content]
        } else if let recordData, let flat = recordData.flatContent {
            [flat]
        } else {
            nil
        }

        let resolvedType = type ?? oldRecord.type
        let existingValues = resolvedType.uppercased() == "MX" && oldRecord.type.uppercased() == "MX"
            ? oldRecord.resourceRecords?.map(\.value) ?? []
            : []
        let newRecord = R53ResourceRecordSet(
            name: resolvedName ?? oldRecord.name,
            type: resolvedType,
            ttl: ttl ?? oldRecord.ttl,
            resourceRecords: resolvedValues.map {
                route53Values(
                    $0,
                    type: resolvedType,
                    priority: priority,
                    recordData: recordData,
                    existingValues: existingValues
                ).map { R53ResourceRecord(value: $0) }
            } ??
                (newAliasTarget != nil ? nil : oldRecord.resourceRecords),
            aliasTarget: newAliasTarget ?? oldRecord.aliasTarget,
            weight: oldRecord.weight,
            region: oldRecord.region,
            geoLocation: oldRecord.geoLocation,
            failover: oldRecord.failover,
            multiValueAnswer: oldRecord.multiValueAnswer,
            setIdentifier: oldRecord.setIdentifier,
            healthCheckId: oldRecord.healthCheckId
        )

        return UpdateR53RecordRequest(
            oldRecord: oldRecord,
            newRecord: newRecord
        )
    }

    func toRoute53Request(oldRecord: R53ResourceRecordSet) -> UpdateR53RecordRequest {
        buildRoute53Request(oldRecord: oldRecord, resolvedName: name)
    }

    func toVercelRequest(domain: String, existingRecord: VercelDNSRecord? = nil) -> UpdateVercelDNSRecordRequest {
        UpdateVercelDNSRecordRequest(
            type: type ?? existingRecord?.type,
            name: name.map { ProviderDNSName.relativeEmptyCaseInsensitive($0, zoneName: domain) },
            value: content ?? recordData?.flatContent,
            ttl: DNSProvider.vercel.normalizeTTL(ttl),
            comment: comment ?? existingRecord?.comment,
            mxPriority: priority ?? existingRecord?.mxPriority ?? existingRecord?.priority ?? existingRecord?.mx
        )
    }

    func toGoogleCloudRequest(oldRecord: GCPResourceRecordSet, zoneName: String) -> GCPResourceRecordSet {
        let gcpType = type ?? oldRecord.type

        let rawContent: [String] = if let values {
            values
        } else if let content {
            if gcpType == "MX", let priority {
                ["\(priority) \(content)"]
            } else {
                [content]
            }
        } else if let recordData, let flat = recordData.flatContent {
            [flat]
        } else {
            oldRecord.rrdatas ?? []
        }
        let gcpContent = googleCloudValues(
            rawContent,
            type: gcpType,
            priority: priority,
            recordData: recordData,
            existingValues: oldRecord.rrdatas ?? []
        )

        return GCPResourceRecordSet(
            name: name.map { ProviderDNSName.absolute($0, in: zoneName, trailingDot: true) } ?? oldRecord.name,
            type: gcpType,
            ttl: ttl ?? oldRecord.ttl,
            rrdatas: gcpContent
        )
    }

    private func resolvedCloudflareData(
        zoneName: String,
        type: String?,
        name: String?,
        content: String?,
        priority: Int?,
        existingData: RecordData?
    ) -> CloudflareRecordData? {
        Self.cloudflareData(
            zoneName: zoneName,
            type: type,
            name: name,
            content: content,
            priority: priority,
            recordData: recordData
        ) ?? existingData.map(CloudflareRecordData.components)
    }

    static func cloudflareData(
        zoneName: String,
        type: String?,
        name: String?,
        content: String?,
        priority: Int?,
        recordData: RecordData?
    ) -> CloudflareRecordData? {
        if let recordData {
            return .components(recordData)
        }
        guard let type, let name, let content else { return nil }

        switch type.uppercased() {
        case "SRV":
            return cloudflareSRVData(
                zoneName: zoneName,
                name: name,
                content: content,
                priority: priority
            ).map(CloudflareRecordData.components)
        case "CAA":
            return cloudflareCAAData(content: content).map(CloudflareRecordData.components)
        default:
            return CloudflareRecordData.parse(type: type, content: content)
        }
    }

    static func cloudflareSRVData(
        zoneName: String,
        name: String,
        content: String,
        priority: Int? = nil
    ) -> RecordData? {
        let nameParts = name.split(separator: ".", maxSplits: 2)
        guard nameParts.count >= 2 else { return nil }

        let service = String(nameParts[0])
        let proto = String(nameParts[1])
        let domain = nameParts.count > 2 ? String(nameParts[2]) : zoneName

        guard let fields = try? ProviderRecordValue.separatingPriority(
            provider: .cloudflare,
            type: "SRV",
            content: content,
            priority: priority,
            recordData: nil,
            acceptsUnprefixedSRV: true
        )
        else { return nil }
        let contentParts = fields.content.split(separator: " ")
        guard contentParts.count >= 3,
              let weight = Int(contentParts[0]),
              let port = Int(contentParts[1])
        else { return nil }

        return RecordData(
            service: service,
            proto: proto,
            name: domain,
            priority: fields.priority,
            weight: weight,
            port: port,
            target: contentParts.dropFirst(2).joined(separator: " ")
        )
    }

    static func cloudflareCAAData(content: String) -> RecordData? {
        let contentParts = content.split(separator: " ", maxSplits: 2)
        guard contentParts.count == 3,
              let flags = Int(contentParts[0])
        else { return nil }

        let tag = String(contentParts[1])
        var caaValue = String(contentParts[2]).trimmed
        if caaValue.hasPrefix("\""), caaValue.hasSuffix("\"") {
            caaValue = String(caaValue.dropFirst().dropLast())
        }

        return RecordData(
            flags: flags,
            tag: tag,
            value: caaValue
        )
    }
}
