import AvgeekLocalizationCore
import Foundation

enum AppLocalization {
    private static let client = AppLocalizationClient(storageKey: SupportedLanguage.storageKey)

    static var locale: Locale {
        client.locale
    }

    static var bundle: Bundle {
        client.bundle
    }

    static func bundle(for language: SupportedLanguage) -> Bundle {
        client.bundle(for: language)
    }

    /// Intentionally accepts LocalizationValue so interpolated values retain
    /// their catalog key and placeholders instead of becoming rendered keys.
    static func string(_ value: String.LocalizationValue) -> String {
        client.string(value)
    }

    static func string(_ value: String.LocalizationValue, language: SupportedLanguage) -> String {
        client.string(value, language: language)
    }
}
