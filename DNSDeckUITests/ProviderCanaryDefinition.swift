import Foundation
import Network

enum ProviderCanaryProfile: String, Sendable {
    case basic
    case comprehensive

    var interactionNames: [String] {
        switch self {
        case .basic:
            [
                "toolbar",
                "csv-file-import",
                "record-types",
                "search",
                "context-menu",
                "bulk-delete",
            ]
        case .comprehensive:
            [
                "toolbar",
                "zone-menu",
                "inline-import",
                "csv-file-import",
                "all-record-types",
                "search",
                "context-menu",
                "clipboard",
                "keyboard",
                "multi-selection",
                "bulk-replace",
                "bulk-delete",
            ]
        }
    }
}

enum ProviderCanaryCredentialFieldKind: Sendable {
    case text
    case secret
}

struct ProviderCanaryCredentialField: Sendable {
    let id: String
    let kind: ProviderCanaryCredentialFieldKind
    let isRequired: Bool
}

enum ProviderCanaryBackendKind: Sendable {
    case cloudflare
}

struct ProviderCanaryDefinition: Sendable {
    let fixtureName: ProviderFixtureName
    let providerID: String
    let displayName: String
    let profile: ProviderCanaryProfile
    let credentialFields: [ProviderCanaryCredentialField]
    let importedRecordTypes: [String]
    let importTTL: Int
    let supportsComments: Bool
    let supportsProxiedRecords: Bool
    let backendKind: ProviderCanaryBackendKind

    var requiredCredentialIDs: [String] {
        credentialFields.filter(\.isRequired).map(\.id)
    }
}

extension ProviderCanaryDefinition {
    static let cloudflare = ProviderCanaryDefinition(
        fixtureName: .cloudflare,
        providerID: "cloudflare",
        displayName: "Cloudflare",
        profile: .comprehensive,
        credentialFields: [
            ProviderCanaryCredentialField(id: "accountId", kind: .text, isRequired: true),
            ProviderCanaryCredentialField(id: "token", kind: .secret, isRequired: true),
        ],
        importedRecordTypes: [
            "A", "AAAA", "CAA", "CNAME", "NS", "DS", "HTTPS",
            "MX", "NAPTR", "PTR", "SRV", "SSHFP", "SVCB", "TLSA",
        ],
        importTTL: 120,
        supportsComments: true,
        supportsProxiedRecords: true,
        backendKind: .cloudflare
    )
}

struct ProviderCanaryConfiguration: Sendable {
    let definition: ProviderCanaryDefinition
    let credentials: [String: String]
    let zoneName: String
    let runPrefix: String

    init(
        definition: ProviderCanaryDefinition,
        fixture: ProviderFixture,
        runPrefix: String
    ) throws {
        let credentials: [String: String]
        do {
            credentials = try Self.decodeCredentials(fixture.credentialsJSON)
        } catch {
            throw ProviderCanaryConfigurationError.invalidCredentials(
                key: definition.fixtureName.credentialsKey,
                requiredFields: definition.requiredCredentialIDs
            )
        }

        let missingFields = definition.requiredCredentialIDs.filter {
            credentials[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
        guard missingFields.isEmpty else {
            throw ProviderCanaryConfigurationError.invalidCredentials(
                key: definition.fixtureName.credentialsKey,
                requiredFields: definition.requiredCredentialIDs
            )
        }

        let zoneName = Self.normalizedDomain(fixture.zone)
        guard Self.isValidDomain(zoneName) else {
            throw ProviderCanaryConfigurationError.invalidZone(
                key: definition.fixtureName.zoneKey
            )
        }

        self.definition = definition
        self.credentials = credentials.mapValues {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.zoneName = zoneName
        self.runPrefix = runPrefix
    }

    var initialContentMarker: String {
        "\(runPrefix)-content-before"
    }

    var updatedContentMarker: String {
        "\(runPrefix)-content-after"
    }

    var primaryRecord: ProviderCanaryRecordFixture {
        record(suffix: "primary")
    }

    var secondaryRecord: ProviderCanaryRecordFixture {
        record(suffix: "secondary")
    }

    var records: [ProviderCanaryRecordFixture] {
        switch definition.profile {
        case .basic: [primaryRecord]
        case .comprehensive: [primaryRecord, secondaryRecord]
        }
    }

    var importedRecords: [ProviderCanaryCSVRecordFixture] {
        definition.importedRecordTypes.map(importedRecord)
    }

    var expectedRecords: [ProviderCanaryExpectedRecordFixture] {
        records.map(\.expectedRecord) + importedRecords.map(\.expectedRecord)
    }

    var expectedRecordTypes: Set<String> {
        Set(expectedRecords.map(\.type))
    }

    func credential(_ id: String) throws -> String {
        guard let value = credentials[id], !value.isEmpty else {
            throw ProviderCanaryConfigurationError.missingCredential(id)
        }
        return value
    }

    func recordNamePresentedByApp(_ fullyQualifiedName: String) -> String {
        fullyQualifiedName
    }

    private nonisolated static func decodeCredentials(_ json: String) throws -> [String: String] {
        let data = Data(json.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderCanaryConfigurationError.invalidCredentialValue
        }

        return try object.mapValues { value in
            if let string = value as? String {
                return string
            }
            guard value is [String: Any], JSONSerialization.isValidJSONObject(value) else {
                throw ProviderCanaryConfigurationError.invalidCredentialValue
            }
            let nestedData = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            guard let nestedJSON = String(data: nestedData, encoding: .utf8) else {
                throw ProviderCanaryConfigurationError.invalidCredentialValue
            }
            return nestedJSON
        }
    }

    func expectedProviderContent(for fixture: ProviderCanaryCSVRecordFixture) -> String {
        if fixture.type == "SRV", definition.backendKind == .cloudflare {
            return fixture.value
                .split(whereSeparator: \Character.isWhitespace)
                .dropFirst()
                .joined(separator: " ")
        }
        if fixture.type == "SSHFP", definition.backendKind == .cloudflare {
            return fixture.value.uppercased()
        }
        guard fixture.type == "CAA" else {
            return fixture.value
        }
        let parts = fixture.value.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return fixture.value }
        let value = parts[2].hasPrefix("\"") && parts[2].hasSuffix("\"")
            ? parts[2]
            : "\"\(parts[2])\""
        return "\(parts[0]) \(parts[1]) \(value)"
    }

    func providerContentMatches(
        _ actualContent: String,
        fixture: ProviderCanaryCSVRecordFixture
    ) -> Bool {
        let expectedContent = expectedProviderContent(for: fixture)
        if ["DS", "SSHFP", "TLSA"].contains(fixture.type) {
            return actualContent.caseInsensitiveCompare(expectedContent) == .orderedSame
        }
        guard fixture.type == "AAAA",
              let actualAddress = IPv6Address(actualContent),
              let expectedAddress = IPv6Address(expectedContent)
        else {
            return actualContent == expectedContent
        }
        return actualAddress == expectedAddress
    }

    func expectedProviderPriority(for fixture: ProviderCanaryCSVRecordFixture) -> Int? {
        if fixture.type == "SRV", definition.backendKind == .cloudflare {
            return fixture.value
                .split(whereSeparator: \Character.isWhitespace)
                .first
                .flatMap { Int($0) }
        }
        return fixture.priority
    }

    func writeCSVImportFixture() throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(runPrefix)-\(definition.providerID)-records.csv")
        let header = "type,name,value,ttl,priority,proxied,comment"
        let rows = importedRecords.map { record in
            [
                record.type,
                record.relativeName,
                record.value,
                String(record.ttl),
                record.priority.map(String.init) ?? "",
                record.proxied.map(String.init) ?? "",
                record.comment ?? "",
            ]
            .map(Self.csvField)
            .joined(separator: ",")
        }
        try ([header] + rows)
            .joined(separator: "\n")
            .appending("\n")
            .write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func record(suffix: String) -> ProviderCanaryRecordFixture {
        let relativeName = "\(runPrefix)-\(suffix)"
        return ProviderCanaryRecordFixture(
            relativeName: relativeName,
            fullyQualifiedName: "\(relativeName).\(zoneName)",
            initialContent: "\(initialContentMarker)-\(suffix)",
            editedContent: "\(initialContentMarker)-\(suffix)-edited",
            updatedContent: "\(updatedContentMarker)-\(suffix)-edited"
        )
    }

    private func importedRecord(type: String) -> ProviderCanaryCSVRecordFixture {
        let delegatedOwner = "\(runPrefix)-delegated"
        let relativeName: String
        let value: String
        let priority: Int?

        switch type {
        case "A":
            (relativeName, value, priority) = ("\(runPrefix)-a", "192.0.2.10", nil)
        case "AAAA":
            (relativeName, value, priority) = ("\(runPrefix)-aaaa", "2001:db8::10", nil)
        case "CAA":
            (relativeName, value, priority) = ("\(runPrefix)-caa", "0 issue letsencrypt.org", nil)
        case "CNAME":
            (relativeName, value, priority) = (
                "\(runPrefix)-cname",
                "target.example.com",
                nil
            )
        case "NS":
            (relativeName, value, priority) = (delegatedOwner, "ns1.example.com", nil)
        case "DS":
            (relativeName, value, priority) = (
                delegatedOwner,
                "2371 13 2 E2D3C916F6DEEAC73294E8268FB5885044A833FC5459588F4A9184CFC41A5766",
                nil
            )
        case "HTTPS":
            (relativeName, value, priority) = ("\(runPrefix)-https", "1 . alpn=\"h2\"", nil)
        case "MX":
            (relativeName, value, priority) = ("\(runPrefix)-mx", "mail.example.com", 10)
        case "NAPTR":
            (relativeName, value, priority) = (
                "\(runPrefix)-naptr",
                "100 10 \"U\" \"E2U+sip\" \"!^.*$!sip:info@example.com!\" .",
                nil
            )
        case "PTR":
            (relativeName, value, priority) = ("\(runPrefix)-ptr", "ptr.example.com", nil)
        case "SRV":
            (relativeName, value, priority) = (
                "_\(runPrefix)-srv._tcp",
                "10 5 443 target.example.com",
                nil
            )
        case "SSHFP":
            (relativeName, value, priority) = (
                "\(runPrefix)-sshfp",
                "1 1 1234567890abcdef1234567890abcdef12345678",
                nil
            )
        case "SVCB":
            (relativeName, value, priority) = ("\(runPrefix)-svcb", "1 . alpn=\"h2\"", nil)
        case "TLSA":
            (relativeName, value, priority) = (
                "\(runPrefix)-tlsa",
                "3 1 1 E2D3C916F6DEEAC73294E8268FB5885044A833FC5459588F4A9184CFC41A5766",
                nil
            )
        default:
            preconditionFailure("Missing provider canary fixture for \(type).")
        }

        let canProxy = definition.supportsProxiedRecords &&
            ["A", "AAAA", "CNAME"].contains(type)
        return ProviderCanaryCSVRecordFixture(
            type: type,
            relativeName: relativeName,
            fullyQualifiedName: "\(relativeName).\(zoneName)",
            value: value,
            ttl: definition.importTTL,
            priority: priority,
            proxied: canProxy ? false : nil,
            comment: definition.supportsComments ? "DNSDeck UI canary \(type)" : nil
        )
    }

    private nonisolated static func normalizedDomain(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t")).lowercased()
    }

    private nonisolated static func isValidDomain(_ value: String) -> Bool {
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 &&
                label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } &&
                label.first != "-" && label.last != "-"
        }
    }

    private nonisolated static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

struct ProviderCanaryRecordFixture: Sendable {
    let relativeName: String
    let fullyQualifiedName: String
    let initialContent: String
    let editedContent: String
    let updatedContent: String

    var expectedRecord: ProviderCanaryExpectedRecordFixture {
        ProviderCanaryExpectedRecordFixture(
            type: "TXT",
            relativeName: relativeName,
            fullyQualifiedName: fullyQualifiedName
        )
    }
}

struct ProviderCanaryCSVRecordFixture: Sendable {
    let type: String
    let relativeName: String
    let fullyQualifiedName: String
    let value: String
    let ttl: Int
    let priority: Int?
    let proxied: Bool?
    let comment: String?

    var expectedRecord: ProviderCanaryExpectedRecordFixture {
        ProviderCanaryExpectedRecordFixture(
            type: type,
            relativeName: relativeName,
            fullyQualifiedName: fullyQualifiedName
        )
    }

    var signature: String {
        expectedRecord.signature
    }
}

struct ProviderCanaryExpectedRecordFixture: Sendable {
    let type: String
    let relativeName: String
    let fullyQualifiedName: String

    var signature: String {
        "\(type) \(fullyQualifiedName)"
    }
}

struct ProviderCanaryLiveValue: Equatable, Sendable {
    let content: String
    let priority: Int?
}

struct ProviderCanaryLiveRecord: Sendable {
    let name: String
    let type: String
    let content: String
    let priority: Int?
    let comment: String?
    let ttl: Int?
    let values: [ProviderCanaryLiveValue]

    init(
        name: String,
        type: String,
        content: String,
        priority: Int?,
        comment: String?,
        ttl: Int? = nil,
        values: [ProviderCanaryLiveValue]? = nil
    ) {
        self.name = name
        self.type = type
        self.content = content
        self.priority = priority
        self.comment = comment
        self.ttl = ttl
        self.values = values ?? [ProviderCanaryLiveValue(content: content, priority: priority)]
    }

    var signature: String {
        "\(type) \(name)"
    }
}

enum ProviderCanaryConfigurationError: LocalizedError {
    case invalidCredentialValue
    case invalidCredentials(key: String, requiredFields: [String])
    case invalidZone(key: String)
    case missingCredential(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentialValue:
            "Provider credentials must contain string fields or nested JSON objects."
        case let .invalidCredentials(key, requiredFields):
            "\(key) must be a JSON object containing non-empty string fields: " +
                requiredFields.joined(separator: ", ")
        case let .invalidZone(key):
            "\(key) must contain a valid existing domain."
        case let .missingCredential(id):
            "The provider canary is missing credential field \(id)."
        }
    }
}

enum ProviderCanaryOwnerMatcher {
    static func isTestRecord(_ name: String, zoneName: String) -> Bool {
        ownerLabels(in: name, zoneName: zoneName).contains {
            $0.hasPrefix("dnsdeck-ui-")
        }
    }

    static func isRunRecord(
        _ name: String,
        zoneName: String,
        runPrefix: String
    ) -> Bool {
        ownerLabels(in: name, zoneName: zoneName).contains {
            $0 == runPrefix || $0.hasPrefix("\(runPrefix)-")
        }
    }

    static func creationDate(_ name: String, zoneName: String) -> Date? {
        ownerLabels(in: name, zoneName: zoneName).compactMap { label -> Date? in
            let components = label.split(separator: "-")
            guard components.count >= 5,
                  components[0] == "dnsdeck",
                  components[1] == "ui",
                  let timestamp = TimeInterval(components[2])
            else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }.first
    }

    private static func ownerLabels(in name: String, zoneName: String) -> [Substring] {
        let normalizedName = name.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let suffix = ".\(zoneName)"
        guard normalizedName.hasSuffix(suffix) else { return [] }
        return normalizedName
            .dropLast(suffix.count)
            .split(separator: ".")
            .map { $0.drop(while: { $0 == "_" }) }
    }
}
