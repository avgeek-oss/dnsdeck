import AvgeekLocalizationCore
import Foundation

enum UITestConfiguration {
    static let isEnabled = ProcessInfo.processInfo.environment["DNSDECK_UI_TESTING"] == "1"
    static let environmentID = UUID(uuidString: "D05DEC00-0000-4000-8000-000000000001")!
    static let environmentName = "DNSDeck UI Tests"

    static func storageKey(_ productionKey: String) -> String {
        isEnabled ? "dnsdeck.ui-tests.\(productionKey)" : productionKey
    }

    static func prepareForLaunch() {
        guard isEnabled else { return }

        let defaults = UserDefaults.standard
        for key in isolatedDefaultsKeys {
            defaults.removeObject(forKey: storageKey(key))
        }
        for provider in DNSProvider.allCases {
            try? provider.deleteCredentials(environmentId: environmentID)
        }
    }

    private static let isolatedDefaultsKeys = [
        "dnsdeck.environments",
        "dnsdeck.settings.selectedSection",
        "dnsdeck.settings.providerEnvironment",
        "dnsdeck.mcp.destination",
        "dnsdeck.showRecordBadges",
        "dnsdeck.showTTLColumn",
        "dnsdeck.showCommentColumn",
        "dnsdeck.dimTypeBadges",
        "dnsdeck.wrapTextContent",
        "dnsdeck.dateTimeFormat",
        SupportedLanguage.storageKey,
        "dnsdeck.enableCache",
        "dnsdeck.zonesCacheTTL",
        "dnsdeck.recordsCacheTTL",
        "dnsdeck.maskContentColumn",
        "dnsdeck.security.autoLockEnabled",
        "dnsdeck.security.autoLockTimeout",
        "dnsdeck.security.isLocked",
    ]
}
