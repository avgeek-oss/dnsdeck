import Foundation

/// The language set supported by Avgeek's Apple applications.
///
/// App-specific persistence keys and String Catalogs deliberately live outside
/// this type so every application can share matching behavior without sharing
/// storage or localized copy.
public enum SupportedLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case brazilianPortuguese = "pt-BR"
    case hindi = "hi"
    case indonesian = "id"
    case turkish = "tr"
    case polish = "pl"
    case ukrainian = "uk"
    case vietnamese = "vi"

    public var id: String {
        rawValue
    }

    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// A stable, self-localized name suitable for an in-app language picker.
    public var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .brazilianPortuguese: "Português (Brasil)"
        case .hindi: "हिन्दी"
        case .indonesian: "Bahasa Indonesia"
        case .turkish: "Türkçe"
        case .polish: "Polski"
        case .ukrainian: "Українська"
        case .vietnamese: "Tiếng Việt"
        }
    }

    /// Returns the first supported language in the OS preference list.
    /// Unsupported preferences are skipped and English is the final fallback.
    public static func bestMatch(for preferredLanguages: [String]) -> SupportedLanguage {
        for identifier in preferredLanguages {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()

            if let exactMatch = allCases.first(where: { $0.rawValue.lowercased() == normalized }) {
                return exactMatch
            }

            let components = normalized.split(separator: "-").map(String.init)
            guard let languageCode = components.first else { continue }

            if languageCode == "zh" {
                let usesTraditionalChinese = components.contains("hant") ||
                    components.contains("tw") ||
                    components.contains("hk") ||
                    components.contains("mo")
                return usesTraditionalChinese ? .traditionalChinese : .simplifiedChinese
            }

            if let languageMatch = allCases.first(where: {
                $0.rawValue.lowercased().split(separator: "-").first == Substring(languageCode)
            }) {
                return languageMatch
            }
        }

        return .english
    }
}
