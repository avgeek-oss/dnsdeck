import Foundation

/// Connects an app-owned persistence key and String Catalog to shared locale
/// resolution. It reads the persisted selection for each request so non-view
/// errors and model labels update immediately after a language change.
public struct AppLocalizationClient {
    public let storageKey: String
    public let userDefaults: UserDefaults
    public let catalog: LocalizationCatalog

    public init(
        storageKey: String,
        userDefaults: UserDefaults = .standard,
        catalog: LocalizationCatalog = .main
    ) {
        self.storageKey = storageKey
        self.userDefaults = userDefaults
        self.catalog = catalog
    }

    public var selectedLanguage: SupportedLanguage {
        guard let identifier = userDefaults.string(forKey: storageKey),
              let language = SupportedLanguage(rawValue: identifier)
        else {
            return catalog.fallbackLanguage
        }
        return language
    }

    public var locale: Locale {
        catalog.locale(for: selectedLanguage)
    }

    public var bundle: Bundle {
        catalog.bundle(for: selectedLanguage)
    }

    public func bundle(for language: SupportedLanguage) -> Bundle {
        catalog.bundle(for: language)
    }

    public func string(_ key: String) -> String {
        catalog.string(key, language: selectedLanguage)
    }

    public func string(_ key: String, language: SupportedLanguage) -> String {
        catalog.string(key, language: language)
    }

    public func string(_ value: String.LocalizationValue) -> String {
        catalog.string(value, language: selectedLanguage)
    }

    public func string(_ value: String.LocalizationValue, language: SupportedLanguage) -> String {
        catalog.string(value, language: language)
    }
}
