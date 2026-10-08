import XCTest
@testable import DNSDeckMCP

final class ConfigurationTests: XCTestCase {
    func testSupportLinksUsePublicDomain() {
        XCTAssertEqual(Configuration.Support.website, "https://dnsdeck.app")
        XCTAssertEqual(Configuration.Support.emailAddress, "support@avgeek.ltd")
        XCTAssertEqual(
            Configuration.Support.mailtoAssistance,
            "mailto:support@avgeek.ltd?subject=I%20need%20assistance%20with%20DNSDeck"
        )
        XCTAssertEqual(
            Configuration.Support.mailtoFeedback,
            "mailto:support@avgeek.ltd?subject=I%20have%20some%20feedback%20for%20DNSDeck"
        )
    }

    func testApplicationIdentityRemainsStable() {
        XCTAssertEqual(Constants.bundleIdentifier, "dev.dnsdeck.DNSDeck")
        XCTAssertEqual(
            Constants.keychainService,
            UITestConfiguration.isEnabled ? "dev.dnsdeck.DNSDeck.ui-tests" : "dev.dnsdeck.DNSDeck"
        )
    }
}
