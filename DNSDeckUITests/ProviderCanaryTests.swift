import XCTest

final class CloudflareProviderUITests: ProviderCanaryTestCase {
    override class var definition: ProviderCanaryDefinition {
        .cloudflare
    }

    func testRecordProviderFlows() async throws {
        try await runProviderCanary()
    }
}

final class GoDaddyProviderUITests: ProviderCanaryTestCase {
    override class var definition: ProviderCanaryDefinition {
        .goDaddy
    }

    func testRecordProviderFlows() async throws {
        try await runProviderCanary()
    }
}

final class IONOSProviderUITests: ProviderCanaryTestCase {
    override class var definition: ProviderCanaryDefinition {
        .ionos
    }

    func testRecordProviderFlows() async throws {
        try await runProviderCanary()
    }
}

final class Route53ProviderUITests: ProviderCanaryTestCase {
    override class var definition: ProviderCanaryDefinition {
        .route53
    }

    func testRecordProviderFlows() async throws {
        try await runProviderCanary()
    }
}
