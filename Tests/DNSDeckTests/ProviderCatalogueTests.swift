import XCTest
@testable import DNSDeckMCP

final class ProviderCatalogueTests: XCTestCase {
    func testEveryCatalogueProviderHasARegisteredSwiftService() throws {
        let registry = ProviderServiceFactory.makeServices(environmentId: UUID())
        for provider in DNSProvider.allCases {
            XCTAssertEqual(try registry.service(for: provider).provider, provider)
        }
    }

    func testEveryProviderHasADedicatedOfflineSuite() {
        let suites: [DNSProvider: XCTestCase.Type] = [
            .cloudflare: CloudflareProviderTests.self,
            .digitalOcean: DigitalOceanProviderTests.self,
            .hetzner: HetznerProviderTests.self,
            .akamaiCloud: AkamaiCloudProviderTests.self,
            .vultr: VultrProviderTests.self,
            .dnsimple: DNSimpleProviderTests.self,
            .gandi: GandiProviderTests.self,
            .goDaddy: GoDaddyProviderTests.self,
            .porkbun: PorkbunProviderTests.self,
            .nameCom: NameComProviderTests.self,
            .namecheap: NamecheapProviderTests.self,
            .spaceship: SpaceshipProviderTests.self,
            .ionos: IONOSProviderTests.self,
            .azureDNS: AzureDNSProviderTests.self,
            .oracleCloud: OracleCloudProviderTests.self,
            .deSEC: DeSECProviderTests.self,
            .powerDNS: PowerDNSProviderTests.self,
            .scaleway: ScalewayProviderTests.self,
            .ovhCloud: OVHCloudProviderTests.self,
            .ibmNS1: IBMNS1ProviderTests.self,
            .ultraDNS: UltraDNSProviderTests.self,
            .route53: Route53ProviderTests.self,
            .vercel: VercelProviderTests.self,
            .googleCloud: GoogleCloudProviderTests.self,
        ]
        XCTAssertEqual(
            Set(suites.keys),
            Set(DNSProvider.allCases),
            "Add an offline provider suite when extending the catalogue"
        )
    }

    func testCredentialKeysAreUniqueAndEditableTypesAreSupported() {
        var storageKeys: Set<String> = []
        for provider in DNSProvider.allCases {
            for field in provider.credentialFields {
                XCTAssertTrue(storageKeys.insert(field.storageKey).inserted, "\(provider): \(field.id)")
            }
            XCTAssertEqual(provider.capabilities.canEdit(recordType: "UNSUPPORTED"), false)
            XCTAssertFalse(provider.credentialFields.isEmpty)
        }
    }
}
