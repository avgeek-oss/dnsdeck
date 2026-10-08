import Foundation

extension Encodable {
    var providerSnapshotData: Data? {
        try? JSONEncoder().encode(self)
    }
}

struct DNSAliasTarget: Codable, Hashable {
    let name: String
    let zoneId: String?
    let evaluateTargetHealth: Bool?
}

struct DNSRecordRoutingPolicy: Codable, Hashable {
    let identifier: String?
    let weight: Int?
    let region: String?
    let continent: String?
    let country: String?
    let subdivision: String?
    let failover: String?
    let multiValueAnswer: Bool?
    let healthCheckId: String?
}

struct ProviderZoneSnapshot: Codable, Hashable {
    let id: String
    let name: String
    var nameservers: [String] = []
    var status: String? = nil
    var createdOn: Date? = nil
    var etag: String? = nil
    var metadata: [String: String] = [:]
    var providerData: Data? = nil
}

struct ProviderRecordSnapshot: Codable, Hashable {
    let id: String
    let name: String
    let type: String
    let values: [String]
    var displayContent: String? = nil
    var ttl: Int? = nil
    var proxied: Bool? = nil
    var priority: Int? = nil
    var comment: String? = nil
    var createdOn: Date? = nil
    var modifiedOn: Date? = nil
    var aliasTarget: DNSAliasTarget? = nil
    var routingPolicy: DNSRecordRoutingPolicy? = nil
    var etag: String? = nil
    var metadata: [String: String] = [:]
    var providerData: Data? = nil

    var content: String {
        displayContent ?? values.joined(separator: "\n")
    }
}
