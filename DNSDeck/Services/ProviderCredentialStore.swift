import Foundation

enum ProviderCredentialStore {
    static func read(provider: DNSProvider, environmentId: UUID) -> [String: String] {
        provider.credentialFields.reduce(into: [:]) { credentials, field in
            let store = KeychainTokenStore(
                service: Constants.keychainService,
                account: field.storageKey,
                environmentId: environmentId
            )
            guard let value = try? store.read(), !value.trimmed.isEmpty else { return }
            credentials[field.id] = value.trimmed
        }
    }

    static func save(
        _ credentials: [String: String],
        provider: DNSProvider,
        environmentId: UUID
    ) throws {
        let previous = read(provider: provider, environmentId: environmentId)

        do {
            try write(credentials, provider: provider, environmentId: environmentId)
        } catch {
            try? write(previous, provider: provider, environmentId: environmentId)
            throw error
        }
    }

    static func delete(provider: DNSProvider, environmentId: UUID) throws {
        try save([:], provider: provider, environmentId: environmentId)
    }

    private static func write(
        _ credentials: [String: String],
        provider: DNSProvider,
        environmentId: UUID
    ) throws {
        for field in provider.credentialFields {
            let store = KeychainTokenStore(
                service: Constants.keychainService,
                account: field.storageKey,
                environmentId: environmentId
            )
            let value = credentials[field.id]?.trimmed ?? ""

            if value.isEmpty {
                try store.delete()
            } else {
                try store.save(value)
            }
        }
    }
}

extension DNSProvider {
    func storedCredentials(environmentId: UUID) -> [String: String] {
        ProviderCredentialStore.read(provider: self, environmentId: environmentId)
    }

    func credentialValue(_ fieldId: String, environmentId: UUID) -> String? {
        storedCredentials(environmentId: environmentId)[fieldId]
    }

    func saveCredentials(_ credentials: [String: String], environmentId: UUID) throws {
        try ProviderCredentialStore.save(credentials, provider: self, environmentId: environmentId)
    }

    func deleteCredentials(environmentId: UUID) throws {
        try ProviderCredentialStore.delete(provider: self, environmentId: environmentId)
    }

    func isConnected(environmentId: UUID) -> Bool {
        let credentials = storedCredentials(environmentId: environmentId)
        return definition.credentialFields
            .filter(\.isRequired)
            .allSatisfy { field in
                guard let value = credentials[field.id] else { return false }
                return !value.trimmed.isEmpty
            }
    }
}
