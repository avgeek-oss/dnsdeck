import AvgeekLocalizationCore
import Foundation
import SwiftUI

/// Owns the persisted in-app language selection shared by Apple app scenes.
/// The first initialization follows the first supported OS preference; every
/// subsequent initialization restores the explicit persisted selection.
@MainActor
public final class AppLanguageController: ObservableObject {
    public let storageKey: String

    private let userDefaults: UserDefaults

    @Published public var appLanguage: SupportedLanguage {
        didSet {
            userDefaults.set(appLanguage.rawValue, forKey: storageKey)
        }
    }

    public init(
        storageKey: String,
        userDefaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.storageKey = storageKey
        self.userDefaults = userDefaults

        if let identifier = userDefaults.string(forKey: storageKey),
           let savedLanguage = SupportedLanguage(rawValue: identifier)
        {
            appLanguage = savedLanguage
        } else {
            let preferredLanguage = SupportedLanguage.bestMatch(for: preferredLanguages)
            appLanguage = preferredLanguage
            userDefaults.set(preferredLanguage.rawValue, forKey: storageKey)
        }
    }

    /// Re-reads the app-owned preference after an external UserDefaults change.
    public func reload() {
        guard let identifier = userDefaults.string(forKey: storageKey),
              let storedLanguage = SupportedLanguage(rawValue: identifier),
              storedLanguage != appLanguage
        else {
            return
        }
        appLanguage = storedLanguage
    }
}
