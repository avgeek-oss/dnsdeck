import AvgeekLocalizationCore
import XCTest

final class LocalizationCoreTests: XCTestCase {
    func testSupportedLanguageSetAndPreferenceMatching() {
        XCTAssertEqual(SupportedLanguage.bestMatch(for: ["it-IT", "pt_BR"]), .brazilianPortuguese)
        XCTAssertEqual(SupportedLanguage.bestMatch(for: ["zh-HK"]), .traditionalChinese)
        XCTAssertEqual(SupportedLanguage.bestMatch(for: ["zh-CN"]), .simplifiedChinese)
        XCTAssertEqual(SupportedLanguage.bestMatch(for: ["ar-SA", "ja-JP"]), .japanese)
        XCTAssertEqual(SupportedLanguage.bestMatch(for: ["ar-SA"]), .english)
        XCTAssertEqual(SupportedLanguage.allCases.count, 15)
    }

    func testExplicitResolverUsesRequestedBundleAndEnglishFallback() throws {
        let catalog = try fixtureCatalog()

        XCTAssertEqual(catalog.resolver(for: .german)("Greeting"), "Hallo")
        XCTAssertEqual(catalog.resolver(for: .japanese)("Greeting"), "Hello")
        XCTAssertEqual(catalog.resolver(for: .german)("Missing key"), "Missing key")
    }

    func testAppLocalizationClientTracksPersistedSelectionAndInvalidFallback() throws {
        let suiteName = "LocalizationCoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let client = try AppLocalizationClient(
            storageKey: "test.language",
            userDefaults: defaults,
            catalog: fixtureCatalog()
        )

        XCTAssertEqual(client.selectedLanguage, .english)
        XCTAssertEqual(client.string("Greeting"), "Hello")

        defaults.set("de", forKey: "test.language")
        XCTAssertEqual(client.selectedLanguage, .german)
        XCTAssertEqual(client.string("Greeting"), "Hallo")

        defaults.set("invalid", forKey: "test.language")
        XCTAssertEqual(client.selectedLanguage, .english)
    }

    private func fixtureCatalog() throws -> LocalizationCatalog {
        let bundleURL = try XCTUnwrap(Bundle.module.url(forResource: "TestCatalog", withExtension: "bundle"))
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        return LocalizationCatalog(bundle: bundle)
    }
}
