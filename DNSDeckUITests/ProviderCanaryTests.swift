import XCTest

final class CloudflareProviderUITests: ProviderCanaryTestCase {
    override class var definition: ProviderCanaryDefinition {
        .cloudflare
    }

    func testRecordProviderFlows() async throws {
        try await runProviderCanary()
    }
}
