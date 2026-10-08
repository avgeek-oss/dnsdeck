import Foundation

// MARK: - Google Cloud DNS Models

/// Service Account Credentials
struct GCPServiceAccount: Codable {
    let project_id: String
    let private_key: String
    let client_email: String
    let token_uri: String
}

/// OAuth Token Response
struct GCPAuthTokenResponse: Codable {
    let access_token: String
    let expires_in: Int
}

/// Managed Zone
struct GCPManagedZone: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let dnsName: String
    let description: String?
    let visibility: String?
    let creationTime: String?
    let nameServers: [String]?

    var dns_name: String {
        dnsName
    }
}

extension GCPManagedZone {
    func snapshot() -> ProviderZoneSnapshot {
        ProviderZoneSnapshot(
            id: id,
            name: dnsName.hasSuffix(".") ? String(dnsName.dropLast()) : dnsName,
            nameservers: nameServers ?? [],
            metadata: [
                "description": description,
                "identifier": name,
                "visibility": visibility,
                "creationTime": creationTime,
            ].compactMapValues { $0 },
            providerData: providerSnapshotData
        )
    }
}

struct GCPCreateManagedZoneRequest: Codable {
    let name: String
    let dnsName: String
    let description: String
    let visibility: String
}

struct GCPDomainRegistration: Codable {
    let dnsSettings: GCPDomainDNSSettings?
}

struct GCPDomainDNSSettings: Codable {
    let customDns: GCPDomainCustomDNS?
}

struct GCPDomainCustomDNS: Codable {
    let nameServers: [String]
    let dsRecords: [GCPDomainDSRecord]?
}

struct GCPDomainDSRecord: Codable {
    let keyTag: Int
    let algorithm: String
    let digestType: String
    let digest: String
}

struct GCPConfigureDNSSettingsRequest: Codable {
    let dnsSettings: GCPDomainDNSSettings
    let updateMask: String
    let validateOnly: Bool
}

/// Resource Record Set
struct GCPResourceRecordSet: Codable, Identifiable, Hashable {
    let name: String
    let type: String
    let ttl: Int
    let rrdatas: [String]?

    var id: String {
        "\(name)-\(type)"
    }
}

extension GCPResourceRecordSet {
    func snapshot() -> ProviderRecordSnapshot {
        let nativeValues = rrdatas ?? []
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
            ttl: ttl,
            priority: priority,
            providerData: providerSnapshotData
        )
    }
}

/// Change Request for DNS operations
struct GCPChange: Codable {
    let kind: String?
    let additions: [GCPResourceRecordSet]?
    let deletions: [GCPResourceRecordSet]?

    init(additions: [GCPResourceRecordSet]? = nil, deletions: [GCPResourceRecordSet]? = nil) {
        kind = "dns#change"
        self.additions = additions
        self.deletions = deletions
    }
}

/// Error Response
struct GCPError: Codable, Error {
    let code: Int?
    let message: String?
    let status: String?
    let details: [GCPErrorDetail]?
}

struct GCPErrorDetail: Codable {
    let type: String?
    let reason: String?
    let domain: String?
    let metadata: [String: String]?
}

/// Response wrapper for API calls
struct GCPResponse: Codable {
    let error: GCPError?
    let managedZones: [GCPManagedZone]?
    let rrsets: [GCPResourceRecordSet]?
    let nextPageToken: String?
}
