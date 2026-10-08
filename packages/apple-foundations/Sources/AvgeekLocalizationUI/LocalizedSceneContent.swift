import AvgeekLocalizationCore
import SwiftUI

private struct LocalizationResolverEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLocalizationResolver(language: .english)
}

public extension EnvironmentValues {
    var avgeekLocalizationResolver: AppLocalizationResolver {
        get { self[LocalizationResolverEnvironmentKey.self] }
        set { self[LocalizationResolverEnvironmentKey.self] = newValue }
    }
}

/// Resolves plain strings against the selected language supplied by the nearest
/// `LocalizedSceneContent` without coupling controls to an app settings type.
@propertyWrapper
public struct AppLocalized: DynamicProperty {
    @Environment(\.avgeekLocalizationResolver) private var resolver

    public init() {}

    public var wrappedValue: AppLocalizationResolver {
        resolver
    }
}

/// Injects locale and explicit string resolution while preserving SwiftUI scene
/// identity when the language changes.
public struct LocalizedSceneContent<Content: View>: View {
    @ObservedObject private var languageController: AppLanguageController
    private let catalog: LocalizationCatalog
    private let content: () -> Content

    public init(
        languageController: AppLanguageController,
        catalog: LocalizationCatalog = .main,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.languageController = languageController
        self.catalog = catalog
        self.content = content
    }

    public var body: some View {
        let language = languageController.appLanguage
        content()
            .environment(\.locale, language.locale)
            .environment(\.avgeekLocalizationResolver, catalog.resolver(for: language))
    }
}
