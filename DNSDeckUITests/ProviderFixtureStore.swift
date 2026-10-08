import Foundation

enum ProviderFixtureName: String {
    case cloudflare = "CLOUDFLARE"

    var credentialsKey: String {
        "PROVIDER_\(rawValue)_CREDENTIALS"
    }

    var zoneKey: String {
        "PROVIDER_\(rawValue)_ZONE"
    }
}

struct ProviderFixture: Sendable {
    let credentialsJSON: String
    let zone: String
}

enum ProviderFixtureStore {
    static func fixture(for provider: ProviderFixtureName) async throws -> ProviderFixture {
        let environment = ProcessInfo.processInfo.environment
        guard let credentials = nonEmpty(environment[provider.credentialsKey]),
              let zone = nonEmpty(environment[provider.zoneKey])
        else {
            throw ProviderFixtureError.missingSecrets(
                credentialsKey: provider.credentialsKey,
                zoneKey: provider.zoneKey
            )
        }
        return ProviderFixture(credentialsJSON: credentials, zone: zone)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ProviderFixtureError: CustomStringConvertible, LocalizedError {
    case missingSecrets(credentialsKey: String, zoneKey: String)

    var errorDescription: String? {
        switch self {
        case let .missingSecrets(credentialsKey, zoneKey):
            "Set \(credentialsKey) and \(zoneKey) to run this live provider test."
        }
    }

    var description: String {
        errorDescription ?? "Provider fixture configuration failed."
    }
}
