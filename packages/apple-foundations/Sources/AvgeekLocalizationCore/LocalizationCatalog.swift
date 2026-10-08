import Foundation

/// Resolves strings from an app-owned localization table for an explicit language.
///
/// Contexts are cached per catalog instance. Missing language bundles fall back
/// to the configured fallback language and then to the source bundle.
public final class LocalizationCatalog: @unchecked Sendable {
    private struct Context {
        let locale: Locale
        let bundle: Bundle
    }

    public static let main = LocalizationCatalog()

    public let sourceBundle: Bundle
    public let tableName: String
    public let fallbackLanguage: SupportedLanguage

    private let contextLock = NSLock()
    private var cachedContexts: [SupportedLanguage: Context] = [:]

    public init(
        bundle: Bundle = .main,
        tableName: String = "Localizable",
        fallbackLanguage: SupportedLanguage = .english
    ) {
        sourceBundle = bundle
        self.tableName = tableName
        self.fallbackLanguage = fallbackLanguage
    }

    public func locale(for language: SupportedLanguage) -> Locale {
        context(for: language).locale
    }

    public func bundle(for language: SupportedLanguage) -> Bundle {
        context(for: language).bundle
    }

    public func string(_ key: String, language: SupportedLanguage) -> String {
        NSLocalizedString(
            key,
            tableName: tableName,
            bundle: bundle(for: language),
            value: key,
            comment: ""
        )
    }

    public func string(_ value: String.LocalizationValue, language: SupportedLanguage) -> String {
        let context = context(for: language)
        return String(
            localized: value,
            table: tableName,
            bundle: context.bundle,
            locale: context.locale
        )
    }

    public func resolver(for language: SupportedLanguage) -> AppLocalizationResolver {
        AppLocalizationResolver(language: language, catalog: self)
    }

    private func context(for language: SupportedLanguage) -> Context {
        contextLock.lock()
        if let cachedContext = cachedContexts[language] {
            contextLock.unlock()
            return cachedContext
        }
        contextLock.unlock()

        let context = Context(
            locale: language.locale,
            bundle: localizedBundle(for: language)
        )

        contextLock.lock()
        cachedContexts[language] = context
        contextLock.unlock()
        return context
    }

    private func localizedBundle(for language: SupportedLanguage) -> Bundle {
        if let bundle = languageBundle(for: language) {
            return bundle
        }
        return languageBundle(for: fallbackLanguage) ?? sourceBundle
    }

    private func languageBundle(for language: SupportedLanguage) -> Bundle? {
        guard let path = sourceBundle.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}

/// A value resolver that prevents plain `String` controls from bypassing the
/// app's explicitly selected language.
public struct AppLocalizationResolver: @unchecked Sendable {
    public let language: SupportedLanguage
    public let catalog: LocalizationCatalog

    public init(
        language: SupportedLanguage,
        catalog: LocalizationCatalog = .main
    ) {
        self.language = language
        self.catalog = catalog
    }

    public func callAsFunction(_ key: String) -> String {
        catalog.string(key, language: language)
    }

    public func callAsFunction(_ value: String.LocalizationValue) -> String {
        catalog.string(value, language: language)
    }
}
