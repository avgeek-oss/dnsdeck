

import Foundation
import Security

protocol TokenStore {
    func save(_ token: String) throws
    func read() throws -> String?
    func delete() throws
}

final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    init(service: String, account: String, environmentId: UUID? = nil) {
        self.service = service
        if let environmentId {
            self.account = "\(environmentId.uuidString).\(account)"
        } else {
            self.account = account
        }
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let match: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let attrs: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(match as CFDictionary, attrs as CFDictionary)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

struct Route53Credentials {
    let accessKeyId: String
    let secretAccessKey: String
}

protocol Route53CredentialsStore {
    func save(_ credentials: Route53Credentials) throws
    func read() throws -> Route53Credentials?
    func delete() throws
}

final class KeychainRoute53CredentialsStore: Route53CredentialsStore {
    private let accessKeyStore: KeychainTokenStore
    private let secretKeyStore: KeychainTokenStore

    init(service: String, environmentId: UUID? = nil) {
        accessKeyStore = KeychainTokenStore(
            service: service,
            account: "route53.access_key_id",
            environmentId: environmentId
        )
        secretKeyStore = KeychainTokenStore(
            service: service,
            account: "route53.secret_access_key",
            environmentId: environmentId
        )
    }

    func save(_ credentials: Route53Credentials) throws {
        try accessKeyStore.save(credentials.accessKeyId)
        try secretKeyStore.save(credentials.secretAccessKey)
    }

    func read() throws -> Route53Credentials? {
        guard let accessKeyId = try accessKeyStore.read(),
              let secretAccessKey = try secretKeyStore.read()
        else {
            return nil
        }
        return Route53Credentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
    }

    func delete() throws {
        let accessError: Error?
        do {
            try accessKeyStore.delete()
            accessError = nil
        } catch {
            accessError = error
        }

        do {
            try secretKeyStore.delete()
        } catch {
            if let accessError {
                throw accessError
            }
            throw error
        }

        if let accessError {
            throw accessError
        }
    }
}
