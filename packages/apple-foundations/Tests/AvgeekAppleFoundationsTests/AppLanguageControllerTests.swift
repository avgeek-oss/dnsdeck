import AvgeekLocalizationCore
import AvgeekLocalizationUI
import XCTest

final class AppLanguageControllerTests: XCTestCase {
    @MainActor
    func testControllerFollowsPreferencesOnceAndPersistsOverride() throws {
        let suiteName = "AppLanguageControllerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = AppLanguageController(
            storageKey: "test.language",
            userDefaults: defaults,
            preferredLanguages: ["vi-VN", "en-US"]
        )
        XCTAssertEqual(initial.appLanguage, .vietnamese)
        XCTAssertEqual(defaults.string(forKey: "test.language"), "vi")

        initial.appLanguage = .german
        let restored = AppLanguageController(
            storageKey: "test.language",
            userDefaults: defaults,
            preferredLanguages: ["ja-JP"]
        )
        XCTAssertEqual(restored.appLanguage, .german)
    }

    @MainActor
    func testControllerReloadsExternalPreferenceChanges() throws {
        let suiteName = "AppLanguageControllerReloadTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = AppLanguageController(
            storageKey: "test.language",
            userDefaults: defaults,
            preferredLanguages: ["en-US"]
        )

        defaults.set("pl", forKey: "test.language")
        controller.reload()

        XCTAssertEqual(controller.appLanguage, .polish)
    }
}
