import Foundation

struct R53HostedZone: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let callerReference: String?
    let config: R53HostedZoneConfig?
    let resourceRecordSetCount: Int?
    var nameServers: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case callerReference = "CallerReference"
        case config = "Config"
        case resourceRecordSetCount = "ResourceRecordSetCount"
        case nameServers = "NameServers"
    }
}

extension R53HostedZone {
    func snapshot() -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: id,
            name: name.hasSuffix(".") ? String(name.dropLast()) : name,
            nameservers: nameServers ?? [],
            metadata: [
                "callerReference": callerReference,
                "comment": config?.comment,
                "privateZone": config?.privateZone.map(String.init),
                "recordCount": resourceRecordSetCount.map(String.init),
            ].compactMapValues { $0 },
            providerData: providerSnapshotData
        )
    }
}

struct R53HostedZoneConfig: Codable, Hashable {
    let privateZone: Bool?
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case privateZone = "PrivateZone"
        case comment = "Comment"
    }
}

struct R53DomainNameserver: Codable, Equatable {
    let name: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
    }
}

struct R53UpdateDomainNameserversRequest: Codable, Equatable {
    let domainName: String
    let nameservers: [R53DomainNameserver]

    enum CodingKeys: String, CodingKey {
        case domainName = "DomainName"
        case nameservers = "Nameservers"
    }
}

/// Route 53 Resource Record Set
struct R53ResourceRecordSet: Codable, Identifiable, Hashable {
    let name: String
    let type: String
    let ttl: Int?
    let resourceRecords: [R53ResourceRecord]?
    let aliasTarget: R53AliasTarget?
    let weight: Int?
    let region: String?
    let geoLocation: R53GeoLocation?
    let failover: String?
    let multiValueAnswer: Bool?
    let setIdentifier: String?
    let healthCheckId: String?

    var id: String {
        // Create a unique identifier combining name, type, and setIdentifier
        let identifier = setIdentifier ?? ""
        return "\(name)|\(type)|\(identifier)"
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case type = "Type"
        case ttl = "TTL"
        case resourceRecords = "ResourceRecords"
        case aliasTarget = "AliasTarget"
        case weight = "Weight"
        case region = "Region"
        case geoLocation = "GeoLocation"
        case failover = "Failover"
        case multiValueAnswer = "MultiValueAnswer"
        case setIdentifier = "SetIdentifier"
        case healthCheckId = "HealthCheckId"
    }
}

extension R53ResourceRecordSet {
    func snapshot() -> ProviderRecordSnapshot {
        let nativeValues = resourceRecords?.map(\.value) ?? aliasTarget.map { [$0.dnsName] } ?? []
        let values: [String]
        let priority: Int?
        switch type.uppercased() {
        case "MX":
            values = nativeValues.map(ProviderRecordValue.removingPriority)
            priority = ProviderRecordValue.commonPriority(nativeValues)
        case "TXT":
            values = nativeValues.map(ProviderRecordValue.parseQuotedTXT)
            priority = nil
        default:
            values = nativeValues
            priority = nil
        }
        return ProviderRecordSnapshot(
            id: id,
            name: name,
            type: type,
            values: values,
            displayContent: values.first ?? "",
            ttl: ttl,
            priority: priority,
            aliasTarget: aliasTarget.map {
                DNSAliasTarget(
                    name: $0.dnsName,
                    zoneId: $0.hostedZoneId,
                    evaluateTargetHealth: $0.evaluateTargetHealth
                )
            },
            routingPolicy: DNSRecordRoutingPolicy(
                identifier: setIdentifier,
                weight: weight,
                region: region,
                continent: geoLocation?.continentCode,
                country: geoLocation?.countryCode,
                subdivision: geoLocation?.subdivisionCode,
                failover: failover,
                multiValueAnswer: multiValueAnswer,
                healthCheckId: healthCheckId
            ),
            providerData: providerSnapshotData
        )
    }
}

struct R53ResourceRecord: Codable, Hashable {
    let value: String

    enum CodingKeys: String, CodingKey {
        case value = "Value"
    }
}

struct R53AliasTarget: Codable, Hashable {
    let dnsName: String
    let hostedZoneId: String
    let evaluateTargetHealth: Bool

    enum CodingKeys: String, CodingKey {
        case dnsName = "DNSName"
        case hostedZoneId = "HostedZoneId"
        case evaluateTargetHealth = "EvaluateTargetHealth"
    }
}

struct R53GeoLocation: Codable, Hashable {
    let continentCode: String?
    let countryCode: String?
    let subdivisionCode: String?

    enum CodingKeys: String, CodingKey {
        case continentCode = "ContinentCode"
        case countryCode = "CountryCode"
        case subdivisionCode = "SubdivisionCode"
    }
}

/// Convenience structures for creating records
struct CreateR53RecordRequest {
    let name: String
    let type: String
    let ttl: Int?
    let values: [String]
    let weight: Int?
    let setIdentifier: String?

    func toResourceRecordSet() -> R53ResourceRecordSet {
        R53ResourceRecordSet(
            name: name,
            type: type,
            ttl: ttl,
            resourceRecords: values.map { R53ResourceRecord(value: $0) },
            aliasTarget: nil,
            weight: weight,
            region: nil,
            geoLocation: nil,
            failover: nil,
            multiValueAnswer: nil,
            setIdentifier: setIdentifier,
            healthCheckId: nil
        )
    }
}

struct UpdateR53RecordRequest {
    let oldRecord: R53ResourceRecordSet
    let newRecord: R53ResourceRecordSet
}
