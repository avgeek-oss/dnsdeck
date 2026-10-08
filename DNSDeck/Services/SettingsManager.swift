import AvgeekLocalizationCore
import AvgeekLocalizationUI
import Combine
import Foundation
import SwiftUI

/// Supported date/time formats
enum DateTimeFormat: String, CaseIterable, Identifiable, Codable {
    case automatic = "auto"
    case relative
    case short
    case medium
    case long
    case iso8601
    case dayMonthYear = "ddmmyyyy"
    case monthDayYear = "mmddyyyy"
    case yearMonthDay = "yyyymmdd"
    case dayMonthYear24 = "ddmmyyyy24"
    case monthDayYear24 = "mmddyyyy24"
    case yearMonthDay24 = "yyyymmdd24"

    var id: String {
        rawValue
    }

    func displayName(localizedBy localize: AppLocalizationResolver) -> String {
        localize(presentation.title)
    }

    private var presentation: (
        title: String,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        format: String?,
        usesUTC: Bool
    ) {
        switch self {
        case .automatic:
            ("Automatic (System Default)", .medium, .short, nil, false)
        case .relative:
            ("Relative (e.g., 2 hours ago)", .none, .none, nil, false)
        case .short:
            ("Short (e.g., 1/15/23, 10:00 AM)", .short, .short, nil, false)
        case .medium:
            ("Medium (e.g., Jan 15, 2023, 10:00 AM)", .medium, .short, nil, false)
        case .long:
            ("Long (e.g., January 15, 2023 at 10:00:00 AM)", .long, .long, nil, false)
        case .iso8601:
            ("ISO 8601 (2023-01-15T10:00:00Z)", .none, .none, "yyyy-MM-dd'T'HH:mm:ss'Z'", true)
        case .dayMonthYear:
            ("DD/MM/YYYY, 12h (15/01/2023, 2:30 PM)", .none, .none, "dd/MM/yyyy, h:mm a", false)
        case .monthDayYear:
            ("MM/DD/YYYY, 12h (01/15/2023, 2:30 PM)", .none, .none, "MM/dd/yyyy, h:mm a", false)
        case .yearMonthDay:
            ("YYYY-MM-DD, 12h (2023-01-15, 2:30 PM)", .none, .none, "yyyy-MM-dd, h:mm a", false)
        case .dayMonthYear24:
            ("DD/MM/YYYY, 24h (15/01/2023, 14:30)", .none, .none, "dd/MM/yyyy, HH:mm", false)
        case .monthDayYear24:
            ("MM/DD/YYYY, 24h (01/15/2023, 14:30)", .none, .none, "MM/dd/yyyy, HH:mm", false)
        case .yearMonthDay24:
            ("YYYY-MM-DD, 24h (2023-01-15, 14:30)", .none, .none, "yyyy-MM-dd, HH:mm", false)
        }
    }

    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = presentation.dateStyle
        formatter.timeStyle = presentation.timeStyle
        if let format = presentation.format {
            formatter.dateFormat = format
        }
        if presentation.usesUTC {
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
        }
        return formatter
    }
}

/// Manages app settings with automatic notification support
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    let languageController: AppLanguageController

    @propertyWrapper
    struct Stored<Value> {
        let key: String
        let defaultValue: Value

        @available(*, unavailable, message: "Stored can only be used on SettingsManager")
        var wrappedValue: Value {
            get { fatalError() }
            set { fatalError() }
        }

        static subscript(
            _enclosingInstance settings: SettingsManager,
            wrapped _: ReferenceWritableKeyPath<SettingsManager, Value>,
            storage storageKeyPath: ReferenceWritableKeyPath<SettingsManager, Self>
        ) -> Value {
            get {
                let setting = settings[keyPath: storageKeyPath]
                return settings.userDefaults.object(forKey: setting.key) as? Value ?? setting.defaultValue
            }
            set {
                let setting = settings[keyPath: storageKeyPath]
                settings.objectWillChange.send()
                settings.userDefaults.set(newValue, forKey: setting.key)
            }
        }
    }

    // MARK: - Settings Keys

    private enum Keys {
        // Interface settings
        static let showRecordBadges = UITestConfiguration.storageKey("dnsdeck.showRecordBadges")
        static let showTTLColumn = UITestConfiguration.storageKey("dnsdeck.showTTLColumn")
        static let showCommentColumn = UITestConfiguration.storageKey("dnsdeck.showCommentColumn")
        static let wrapTextContent = UITestConfiguration.storageKey("dnsdeck.wrapTextContent")
        static let dateTimeFormat = UITestConfiguration.storageKey("dnsdeck.dateTimeFormat")
        static let appLanguage = UITestConfiguration.storageKey(SupportedLanguage.storageKey)

        // Cache settings
        static let enableCache = UITestConfiguration.storageKey("dnsdeck.enableCache")
        static let zonesCacheTTL = UITestConfiguration.storageKey("dnsdeck.zonesCacheTTL")
        static let recordsCacheTTL = UITestConfiguration.storageKey("dnsdeck.recordsCacheTTL")

        /// Privacy settings
        static let maskContentColumn = UITestConfiguration.storageKey("dnsdeck.maskContentColumn")
    }

    // MARK: - Published Properties

    @Stored(key: Keys.showRecordBadges, defaultValue: true) var showRecordBadges: Bool
    @Stored(key: Keys.showTTLColumn, defaultValue: true) var showTTLColumn: Bool
    @Stored(key: Keys.showCommentColumn, defaultValue: true) var showCommentColumn: Bool
    @Stored(key: Keys.maskContentColumn, defaultValue: false) var maskContentColumn: Bool
    @Stored(key: Keys.wrapTextContent, defaultValue: false) var wrapTextContent: Bool

    var dateTimeFormat: DateTimeFormat {
        get { userDefaults.string(forKey: Keys.dateTimeFormat).flatMap(DateTimeFormat.init) ?? .automatic }
        set {
            objectWillChange.send()
            userDefaults.set(newValue.rawValue, forKey: Keys.dateTimeFormat)
        }
    }

    var appLanguage: SupportedLanguage {
        get { languageController.appLanguage }
        set { languageController.appLanguage = newValue }
    }

    // MARK: - Cache Settings

    @Stored(key: Keys.enableCache, defaultValue: true) var enableCache: Bool
    @Stored(key: Keys.zonesCacheTTL, defaultValue: 30 * 60) var zonesCacheTTL: TimeInterval
    @Stored(key: Keys.recordsCacheTTL, defaultValue: 5 * 60) var recordsCacheTTL: TimeInterval

    // MARK: - Initialization

    private init() {
        languageController = AppLanguageController(storageKey: Keys.appLanguage)

        languageController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshFromUserDefaults()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func refreshFromUserDefaults() {
        objectWillChange.send()
        languageController.reload()
    }
}
