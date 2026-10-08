import Foundation

enum Constants {
    // App Configuration
    static let bundleIdentifier = "dev.dnsdeck.DNSDeck"
    static var keychainService: String {
        UITestConfiguration.isEnabled ? "dev.dnsdeck.DNSDeck.ui-tests" : bundleIdentifier
    }

    /// Pagination
    enum Pagination {
        static let cloudflarePageSize = 50
        static let cloudflareMaxPageSize = 100
        static let route53PageSize = 100
        static let route53MaxPageSize = 300
        static let vercelPageSize = 50
        static let vercelMaxPageSize = 100
        static let googleCloudPageSize = 100
        static let googleCloudMaxPageSize = 500
    }

    /// DNS Record Types
    enum DNSRecordTypes {
        static let proxyableTypes = ["A", "AAAA", "CNAME"]
        static let supportedTypes = [
            "A", "AAAA", "ALIAS", "CAA", "CNAME", "DNAME", "DS", "HINFO", "HTTPS", "MX", "NAPTR", "NS", "PTR",
            "RP", "SRV", "SSHFP", "SVCB", "TLSA", "TXT",
        ]
    }

    /// TTL Values
    enum TTL {
        static let automatic = 1
        static let minimum = 60
        static let maximum = 86400
    }

    /// UI Constants
    enum UI {
        #if os(macOS)
        static let defaultWindowWidth: CGFloat = 1280
        static let defaultWindowHeight: CGFloat = 800
        static let minimumWindowWidth: CGFloat = 900
        static let minimumWindowHeight: CGFloat = 560
        static let minimumZoneListWidth: CGFloat = 280
        static let preferredZoneListWidth: CGFloat = 300
        static let maximumZoneListWidth: CGFloat = 380
        #endif

        static let tableColumnMinWidth: CGFloat = 160
        static let contentColumnMinWidth: CGFloat = 240
        static let minimumEnvironmentListWidth: CGFloat = 200

        /// Design tokens
        static let cornerRadiusBadge: CGFloat = 4
    }

    /// UI Text
    enum UIText {
        static var loadingZones: String {
            localized("Loading zones…")
        }

        static var loadingRecords: String {
            localized("Loading records…")
        }

        static var loading: String {
            localized("Loading...")
        }

        /// Actions
        static var addRecord: String {
            localized("Add record")
        }

        static var copyRecordName: String {
            localized("Copy record name")
        }

        static var copyRecordValue: String {
            localized("Copy record value")
        }

        /// Alerts
        static var deleteRecords: String {
            localized("Delete Records?")
        }

        static var deleteRecord: String {
            localized("Delete Record?")
        }

        private static func localized(_ key: String.LocalizationValue) -> String {
            AppLocalization.string(key)
        }
    }
}
