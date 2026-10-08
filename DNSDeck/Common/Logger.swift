import Foundation
import os.log

enum Logger {
    private static let subsystem = Constants.bundleIdentifier

    static let network = os.Logger(subsystem: subsystem, category: "Network")
    static let keychain = os.Logger(subsystem: subsystem, category: "Keychain")
    static let ui = os.Logger(subsystem: subsystem, category: "UI")
    static let dns = os.Logger(subsystem: subsystem, category: "DNS")
    static let cache = os.Logger(subsystem: subsystem, category: "Cache")
    static let general = os.Logger(subsystem: subsystem, category: "General")

    static func logError(_ error: Error, context: String) {
        general.error("💥 Error in \(context): \(error.localizedDescription)")
    }
}
