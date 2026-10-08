import Foundation

@dynamicMemberLookup
enum DNSProvider: String, CaseIterable, Codable, Identifiable, Hashable {
    case cloudflare
    case digitalOcean
    case hetzner
    case akamaiCloud
    case vultr
    case dnsimple
    case gandi
    case goDaddy
    case porkbun
    case nameCom
    case namecheap
    case spaceship
    case ionos
    case azureDNS
    case oracleCloud
    case deSEC
    case powerDNS
    case scaleway
    case ovhCloud
    case ibmNS1
    case ultraDNS
    case route53
    case vercel
    case googleCloud

    var id: String {
        rawValue
    }

    var definition: ProviderDefinition {
        guard let definition = Self.definitions[self] else {
            preconditionFailure("Missing provider definition for \(rawValue)")
        }
        return definition
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<ProviderDefinition, Value>) -> Value {
        definition[keyPath: keyPath]
    }

    var supportsZoneCreation: Bool {
        definition.capabilities.zoneCapabilities.contains(.create)
    }

    var defaultTTL: Int {
        definition.capabilities.ttl.defaultValue
    }

    var supportsAutoTTL: Bool {
        definition.capabilities.ttl.supportsAutomatic
    }

    var minTTL: Int {
        definition.capabilities.ttl.minimum
    }

    var maxTTL: Int {
        definition.capabilities.ttl.maximum
    }

    var ttlHelpText: LocalizedStringResource {
        definition.capabilities.ttl.helpText
    }

    func normalizeTTL(_ ttl: Int?) -> Int? {
        definition.capabilities.ttl.normalize(ttl)
    }

    func getEffectiveTTL(_ ttl: Int?) -> Int? {
        ttl.map(normalizeTTL) ?? defaultTTL
    }

    private static let definitions = ProviderDefinitionCatalog.load()
}
