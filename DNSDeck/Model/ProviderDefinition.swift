import Foundation

enum ProviderCredentialFieldKind: String, Codable, Hashable {
    case text
    case secret
    case multilineSecret
}

struct ProviderCredentialField: Identifiable {
    let id: String
    let label: LocalizedStringResource
    let storageKey: String
    let kind: ProviderCredentialFieldKind
    let isRequired: Bool
    let helpText: LocalizedStringResource?

    init(
        id: String,
        label: LocalizedStringResource,
        storageKey: String,
        kind: ProviderCredentialFieldKind,
        isRequired: Bool = true,
        helpText: LocalizedStringResource? = nil
    ) {
        self.id = id
        self.label = label
        self.storageKey = storageKey
        self.kind = kind
        self.isRequired = isRequired
        self.helpText = helpText
    }
}

enum ProviderZoneCapability: String, Codable, Hashable {
    case list
    case details
    case create
    case delete
    case updateNameservers
}

struct ProviderNameserverPolicy: Hashable {
    let minimumCount: Int
    let maximumCount: Int

    static let standard = ProviderNameserverPolicy(minimumCount: 2, maximumCount: 12)
}

enum ProviderRecordMutationMode: String, Codable, Hashable {
    case individualRecord
    case recordSetReplacement
    case transactionalBatch
    case wholeZoneReplacement
}

enum ProviderFeature: String, Codable, Hashable {
    case aliases
    case comments
    case privateZones
    case proxy
    case routingPolicies
    case zoneNameservers
}

struct ProviderTTLPolicy {
    let defaultValue: Int
    let minimum: Int
    let maximum: Int
    let automaticValue: Int?
    let usesInheritedTTLForAutomatic: Bool
    let allowedValues: [Int]?
    let helpText: LocalizedStringResource

    init(
        defaultValue: Int,
        minimum: Int,
        maximum: Int,
        automaticValue: Int?,
        usesInheritedTTLForAutomatic: Bool = false,
        allowedValues: [Int]? = nil,
        helpText: LocalizedStringResource
    ) {
        self.defaultValue = defaultValue
        self.minimum = minimum
        self.maximum = maximum
        self.automaticValue = automaticValue
        self.usesInheritedTTLForAutomatic = usesInheritedTTLForAutomatic
        self.allowedValues = allowedValues?.sorted()
        self.helpText = helpText
    }

    var supportsAutomatic: Bool {
        automaticValue != nil || usesInheritedTTLForAutomatic
    }

    func normalize(_ ttl: Int?) -> Int? {
        guard let ttl else { return nil }

        if ttl == Constants.TTL.automatic, let automaticValue {
            return automaticValue
        }
        if ttl == Constants.TTL.automatic, usesInheritedTTLForAutomatic {
            return nil
        }

        let boundedTTL = max(minimum, min(maximum, ttl))
        guard let allowedValues, !allowedValues.isEmpty else { return boundedTTL }
        return allowedValues.first(where: { $0 >= boundedTTL }) ?? allowedValues.last
    }
}

struct ProviderCapabilities {
    let zoneCapabilities: Set<ProviderZoneCapability>
    let recordMutationMode: ProviderRecordMutationMode
    let editableRecordTypes: [String]
    let features: Set<ProviderFeature>
    let ttl: ProviderTTLPolicy

    func canEdit(recordType: String) -> Bool {
        editableRecordTypes.contains(recordType.uppercased())
    }
}

struct ProviderSetupLink {
    let title: LocalizedStringResource
    let url: URL
}

struct ProviderDefinition {
    let displayName: String
    let description: LocalizedStringResource
    let imageAssetName: String?
    let symbolName: String
    let setupLink: ProviderSetupLink?
    let credentialFields: [ProviderCredentialField]
    let capabilities: ProviderCapabilities
}

private struct ProviderDefinitionSpec: Decodable {
    struct Setup: Decodable {
        let title: String
        let url: URL
    }

    struct Credential: Decodable {
        let id: String
        let label: String
        let storageKey: String
        let kind: ProviderCredentialFieldKind
        let required: Bool
        let help: String?
    }

    struct TTL: Decodable {
        let `default`: Int
        let minimum: Int
        let maximum: Int
        let automatic: Int?
        let inherited: Bool
        let allowed: [Int]?
        let help: String
    }

    let provider: DNSProvider
    let name: String
    let description: String
    let asset: String?
    let symbol: String
    let setup: Setup?
    let credentials: [Credential]
    let zones: Set<ProviderZoneCapability>
    let mode: ProviderRecordMutationMode
    let records: [String]
    let features: Set<ProviderFeature>
    let ttl: TTL

    var definition: ProviderDefinition {
        ProviderDefinition(
            displayName: name,
            description: localized(description),
            imageAssetName: asset,
            symbolName: symbol,
            setupLink: setup.map { ProviderSetupLink(title: localized($0.title), url: $0.url) },
            credentialFields: credentials.map {
                ProviderCredentialField(
                    id: $0.id,
                    label: localized($0.label),
                    storageKey: $0.storageKey,
                    kind: $0.kind,
                    isRequired: $0.required,
                    helpText: $0.help.map(localized)
                )
            },
            capabilities: ProviderCapabilities(
                zoneCapabilities: zones,
                recordMutationMode: mode,
                editableRecordTypes: records,
                features: features,
                ttl: ProviderTTLPolicy(
                    defaultValue: ttl.default,
                    minimum: ttl.minimum,
                    maximum: ttl.maximum,
                    automaticValue: ttl.automatic,
                    usesInheritedTTLForAutomatic: ttl.inherited,
                    allowedValues: ttl.allowed,
                    helpText: localized(ttl.help)
                )
            )
        )
    }

    private func localized(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(stringLiteral: key))
    }
}

enum ProviderDefinitionCatalog {
    static func load(bundle: Bundle? = nil) -> [DNSProvider: ProviderDefinition] {
        let bundle = bundle ?? resourceBundle
        guard let url = bundle.url(forResource: "ProviderDefinitions", withExtension: "json"),
              let specs = try? JSONDecoder().decode([ProviderDefinitionSpec].self, from: Data(contentsOf: url)),
              specs.count == DNSProvider.allCases.count
        else {
            preconditionFailure("ProviderDefinitions.json is missing or incomplete")
        }
        return Dictionary(uniqueKeysWithValues: specs.map { ($0.provider, $0.definition) })
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}
