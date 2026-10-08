import XCTest
@testable import DNSDeckMCP

final class DNSProviderTests: XCTestCase {
    // MARK: - Provider Properties

    func testAllCases() {
        let allCases = DNSProvider.allCases
        XCTAssertEqual(allCases.count, 24)
        XCTAssertTrue(allCases.contains(.namecheap))
        XCTAssertTrue(allCases.contains(.cloudflare))
        XCTAssertTrue(allCases.contains(.digitalOcean))
        XCTAssertTrue(allCases.contains(.hetzner))
        XCTAssertTrue(allCases.contains(.akamaiCloud))
        XCTAssertTrue(allCases.contains(.vultr))
        XCTAssertTrue(allCases.contains(.dnsimple))
        XCTAssertTrue(allCases.contains(.gandi))
        XCTAssertTrue(allCases.contains(.goDaddy))
        XCTAssertTrue(allCases.contains(.porkbun))
        XCTAssertTrue(allCases.contains(.nameCom))
        XCTAssertTrue(allCases.contains(.spaceship))
        XCTAssertTrue(allCases.contains(.ionos))
        XCTAssertTrue(allCases.contains(.azureDNS))
        XCTAssertTrue(allCases.contains(.oracleCloud))
        XCTAssertTrue(allCases.contains(.deSEC))
        XCTAssertTrue(allCases.contains(.powerDNS))
        XCTAssertTrue(allCases.contains(.scaleway))
        XCTAssertTrue(allCases.contains(.ovhCloud))
        XCTAssertTrue(allCases.contains(.ibmNS1))
        XCTAssertTrue(allCases.contains(.ultraDNS))
        XCTAssertTrue(allCases.contains(.route53))
        XCTAssertTrue(allCases.contains(.vercel))
        XCTAssertTrue(allCases.contains(.googleCloud))
    }

    func testProviderIDs() {
        XCTAssertEqual(DNSProvider.cloudflare.id, "cloudflare")
        XCTAssertEqual(DNSProvider.digitalOcean.id, "digitalOcean")
        XCTAssertEqual(DNSProvider.hetzner.id, "hetzner")
        XCTAssertEqual(DNSProvider.akamaiCloud.id, "akamaiCloud")
        XCTAssertEqual(DNSProvider.vultr.id, "vultr")
        XCTAssertEqual(DNSProvider.dnsimple.id, "dnsimple")
        XCTAssertEqual(DNSProvider.gandi.id, "gandi")
        XCTAssertEqual(DNSProvider.goDaddy.id, "goDaddy")
        XCTAssertEqual(DNSProvider.porkbun.id, "porkbun")
        XCTAssertEqual(DNSProvider.nameCom.id, "nameCom")
        XCTAssertEqual(DNSProvider.spaceship.id, "spaceship")
        XCTAssertEqual(DNSProvider.ionos.id, "ionos")
        XCTAssertEqual(DNSProvider.azureDNS.id, "azureDNS")
        XCTAssertEqual(DNSProvider.oracleCloud.id, "oracleCloud")
        XCTAssertEqual(DNSProvider.deSEC.id, "deSEC")
        XCTAssertEqual(DNSProvider.powerDNS.id, "powerDNS")
        XCTAssertEqual(DNSProvider.scaleway.id, "scaleway")
        XCTAssertEqual(DNSProvider.ovhCloud.id, "ovhCloud")
        XCTAssertEqual(DNSProvider.ibmNS1.id, "ibmNS1")
        XCTAssertEqual(DNSProvider.ultraDNS.id, "ultraDNS")
        XCTAssertEqual(DNSProvider.route53.id, "route53")
        XCTAssertEqual(DNSProvider.vercel.id, "vercel")
        XCTAssertEqual(DNSProvider.googleCloud.id, "googleCloud")
    }

    func testDisplayNames() {
        XCTAssertEqual(DNSProvider.cloudflare.displayName, "Cloudflare")
        XCTAssertEqual(DNSProvider.digitalOcean.displayName, "DigitalOcean")
        XCTAssertEqual(DNSProvider.hetzner.displayName, "Hetzner")
        XCTAssertEqual(DNSProvider.akamaiCloud.displayName, "Akamai Cloud (Linode)")
        XCTAssertEqual(DNSProvider.vultr.displayName, "Vultr")
        XCTAssertEqual(DNSProvider.dnsimple.displayName, "DNSimple")
        XCTAssertEqual(DNSProvider.gandi.displayName, "Gandi LiveDNS")
        XCTAssertEqual(DNSProvider.goDaddy.displayName, "GoDaddy")
        XCTAssertEqual(DNSProvider.porkbun.displayName, "Porkbun")
        XCTAssertEqual(DNSProvider.nameCom.displayName, "Name.com")
        XCTAssertEqual(DNSProvider.spaceship.displayName, "Spaceship")
        XCTAssertEqual(DNSProvider.ionos.displayName, "IONOS")
        XCTAssertEqual(DNSProvider.azureDNS.displayName, "Azure DNS")
        XCTAssertEqual(DNSProvider.oracleCloud.displayName, "Oracle Cloud DNS")
        XCTAssertEqual(DNSProvider.deSEC.displayName, "deSEC")
        XCTAssertEqual(DNSProvider.powerDNS.displayName, "PowerDNS Authoritative")
        XCTAssertEqual(DNSProvider.scaleway.displayName, "Scaleway Domains and DNS")
        XCTAssertEqual(DNSProvider.ovhCloud.displayName, "OVHcloud DNS")
        XCTAssertEqual(DNSProvider.ibmNS1.displayName, "IBM NS1 Connect")
        XCTAssertEqual(DNSProvider.ultraDNS.displayName, "UltraDNS")
        XCTAssertEqual(DNSProvider.route53.displayName, "Amazon Route 53")
        XCTAssertEqual(DNSProvider.vercel.displayName, "Vercel")
        XCTAssertEqual(DNSProvider.googleCloud.displayName, "Google Cloud DNS")
    }

    func testProviderImageAssets() {
        let expected: [DNSProvider: String] = [
            .cloudflare: "Cloudflare",
            .digitalOcean: "DigitalOcean",
            .hetzner: "Hetzner",
            .akamaiCloud: "Akamai Cloud",
            .vultr: "Vultr",
            .dnsimple: "DNSimple",
            .gandi: "Gandi LiveDNS",
            .goDaddy: "GoDaddy",
            .porkbun: "Porkbun",
            .nameCom: "Name.com",
            .ionos: "IONOS",
            .azureDNS: "Azure DNS",
            .oracleCloud: "Oracle Cloud DNS",
            .deSEC: "deSEC",
            .powerDNS: "PowerDNS Authoritative",
            .scaleway: "Scaleway",
            .ovhCloud: "OVHcloud DNS",
            .ibmNS1: "IBM NS1 Connect",
            .ultraDNS: "UltraDNS",
            .route53: "Amazon Route 53",
            .vercel: "Vercel",
            .googleCloud: "Google Cloud",
        ]

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: DNSProvider.allCases.compactMap { provider in
                provider.imageAssetName.map { (provider, $0) }
            }),
            expected
        )
    }

    func testSymbolNames() {
        XCTAssertEqual(DNSProvider.cloudflare.symbolName, "cloud")
        XCTAssertEqual(DNSProvider.digitalOcean.symbolName, "drop")
        XCTAssertEqual(DNSProvider.hetzner.symbolName, "server.rack")
        XCTAssertEqual(DNSProvider.akamaiCloud.symbolName, "cloud")
        XCTAssertEqual(DNSProvider.vultr.symbolName, "server.rack")
        XCTAssertEqual(DNSProvider.dnsimple.symbolName, "network")
        XCTAssertEqual(DNSProvider.gandi.symbolName, "globe.europe.africa")
        XCTAssertEqual(DNSProvider.goDaddy.symbolName, "globe.americas")
        XCTAssertEqual(DNSProvider.porkbun.symbolName, "globe.asia.australia")
        XCTAssertEqual(DNSProvider.nameCom.symbolName, "network")
        XCTAssertEqual(DNSProvider.spaceship.symbolName, "airplane")
        XCTAssertEqual(DNSProvider.ionos.symbolName, "globe.europe.africa")
        XCTAssertEqual(DNSProvider.azureDNS.symbolName, "cloud")
        XCTAssertEqual(DNSProvider.oracleCloud.symbolName, "cloud")
        XCTAssertEqual(DNSProvider.deSEC.symbolName, "lock.shield")
        XCTAssertEqual(DNSProvider.powerDNS.symbolName, "server.rack")
        XCTAssertEqual(DNSProvider.scaleway.symbolName, "cloud")
        XCTAssertEqual(DNSProvider.ovhCloud.symbolName, "globe.europe.africa")
        XCTAssertEqual(DNSProvider.ibmNS1.symbolName, "network")
        XCTAssertEqual(DNSProvider.ultraDNS.symbolName, "network")
        XCTAssertEqual(DNSProvider.route53.symbolName, "server.rack")
        XCTAssertEqual(DNSProvider.vercel.symbolName, "triangle")
        XCTAssertEqual(DNSProvider.googleCloud.symbolName, "globe")
    }

    func testCredentialDescriptors() {
        XCTAssertEqual(DNSProvider.cloudflare.credentialFields.map(\.id), ["accountId", "token"])
        XCTAssertTrue(DNSProvider.cloudflare.credentialFields.allSatisfy(\.isRequired))

        XCTAssertEqual(DNSProvider.digitalOcean.credentialFields.map(\.id), ["token"])
        XCTAssertTrue(DNSProvider.digitalOcean.credentialFields[0].isRequired)

        XCTAssertEqual(DNSProvider.hetzner.credentialFields.map(\.id), ["token"])
        XCTAssertTrue(DNSProvider.hetzner.credentialFields[0].isRequired)

        XCTAssertEqual(DNSProvider.akamaiCloud.credentialFields.map(\.id), ["token"])
        XCTAssertTrue(DNSProvider.akamaiCloud.credentialFields[0].isRequired)

        XCTAssertEqual(DNSProvider.vultr.credentialFields.map(\.id), ["token"])
        XCTAssertTrue(DNSProvider.vultr.credentialFields[0].isRequired)

        XCTAssertEqual(DNSProvider.dnsimple.credentialFields.map(\.id), ["accountId", "token"])
        XCTAssertTrue(DNSProvider.dnsimple.credentialFields.allSatisfy(\.isRequired))

        XCTAssertEqual(DNSProvider.gandi.credentialFields.map(\.id), ["token"])
        XCTAssertTrue(DNSProvider.gandi.credentialFields[0].isRequired)

        XCTAssertEqual(DNSProvider.goDaddy.credentialFields.map(\.id), ["token", "shopperId"])
        XCTAssertFalse(DNSProvider.goDaddy.credentialFields[1].isRequired)

        XCTAssertEqual(DNSProvider.porkbun.credentialFields.map(\.id), ["apiKey", "secretApiKey"])
        XCTAssertTrue(DNSProvider.porkbun.credentialFields.allSatisfy(\.isRequired))

        XCTAssertEqual(DNSProvider.nameCom.credentialFields.map(\.id), ["username", "token"])
        XCTAssertTrue(DNSProvider.nameCom.credentialFields.allSatisfy(\.isRequired))

        XCTAssertEqual(DNSProvider.spaceship.credentialFields.map(\.id), ["apiKey", "apiSecret"])
        XCTAssertTrue(DNSProvider.spaceship.credentialFields.allSatisfy(\.isRequired))

        XCTAssertEqual(DNSProvider.ionos.credentialFields.map(\.id), ["apiKey"])
        XCTAssertTrue(DNSProvider.ionos.credentialFields[0].isRequired)

        XCTAssertEqual(
            DNSProvider.azureDNS.credentialFields.map(\.id),
            ["tenantId", "clientId", "clientSecret", "subscriptionId", "resourceGroup"]
        )
        XCTAssertFalse(DNSProvider.azureDNS.credentialFields[4].isRequired)

        XCTAssertEqual(
            DNSProvider.oracleCloud.credentialFields.map(\.id),
            ["tenancyId", "userId", "fingerprint", "privateKeyPEM", "region", "compartmentId", "realmDomain"]
        )
        XCTAssertEqual(DNSProvider.oracleCloud.credentialFields[3].kind, .multilineSecret)
        XCTAssertFalse(DNSProvider.oracleCloud.credentialFields[6].isRequired)

        XCTAssertEqual(DNSProvider.deSEC.credentialFields.map(\.id), ["token"])
        XCTAssertTrue(DNSProvider.deSEC.credentialFields[0].isRequired)

        XCTAssertEqual(
            DNSProvider.powerDNS.credentialFields.map(\.id),
            ["endpoint", "apiKey", "serverId", "nameserver"]
        )
        XCTAssertFalse(DNSProvider.powerDNS.credentialFields[2].isRequired)
        XCTAssertFalse(DNSProvider.powerDNS.credentialFields[3].isRequired)

        XCTAssertEqual(DNSProvider.scaleway.credentialFields.map(\.id), ["secretKey", "projectId"])
        XCTAssertTrue(DNSProvider.scaleway.credentialFields.allSatisfy(\.isRequired))

        XCTAssertEqual(
            DNSProvider.ovhCloud.credentialFields.map(\.id),
            ["endpoint", "applicationKey", "applicationSecret", "consumerKey"]
        )
        XCTAssertTrue(DNSProvider.ovhCloud.credentialFields.allSatisfy(\.isRequired))

        XCTAssertEqual(DNSProvider.ibmNS1.credentialFields.map(\.id), ["apiKey"])
        XCTAssertTrue(DNSProvider.ibmNS1.credentialFields[0].isRequired)

        XCTAssertEqual(DNSProvider.ultraDNS.credentialFields.map(\.id), ["username", "password"])
        XCTAssertTrue(DNSProvider.ultraDNS.credentialFields.allSatisfy(\.isRequired))

        XCTAssertEqual(DNSProvider.route53.credentialFields.map(\.id), ["accessKeyId", "secretAccessKey"])
        XCTAssertTrue(DNSProvider.route53.credentialFields.allSatisfy(\.isRequired))

        XCTAssertEqual(DNSProvider.vercel.credentialFields.map(\.id), ["token", "teamId"])
        XCTAssertFalse(DNSProvider.vercel.credentialFields[1].isRequired)

        XCTAssertEqual(
            DNSProvider.googleCloud.credentialFields.map(\.id),
            ["projectId", "serviceAccountJSON"]
        )
        XCTAssertEqual(DNSProvider.googleCloud.credentialFields[1].kind, .multilineSecret)
    }

    func testCapabilityDefinitions() {
        XCTAssertEqual(DNSProvider.cloudflare.capabilities.recordMutationMode, .individualRecord)
        XCTAssertEqual(DNSProvider.digitalOcean.capabilities.recordMutationMode, .individualRecord)
        XCTAssertTrue(DNSProvider.digitalOcean.capabilities.zoneCapabilities.contains(.delete))
        XCTAssertTrue(DNSProvider.digitalOcean.capabilities.canEdit(recordType: "SRV"))
        XCTAssertFalse(DNSProvider.digitalOcean.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.hetzner.capabilities.recordMutationMode, .recordSetReplacement)
        XCTAssertTrue(DNSProvider.hetzner.capabilities.canEdit(recordType: "HTTPS"))
        XCTAssertFalse(DNSProvider.hetzner.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.akamaiCloud.capabilities.recordMutationMode, .individualRecord)
        XCTAssertTrue(DNSProvider.akamaiCloud.capabilities.canEdit(recordType: "CAA"))
        XCTAssertEqual(DNSProvider.vultr.capabilities.recordMutationMode, .individualRecord)
        XCTAssertTrue(DNSProvider.vultr.capabilities.canEdit(recordType: "SSHFP"))
        XCTAssertEqual(DNSProvider.dnsimple.capabilities.recordMutationMode, .individualRecord)
        XCTAssertTrue(DNSProvider.dnsimple.capabilities.canEdit(recordType: "ALIAS"))
        XCTAssertFalse(DNSProvider.dnsimple.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.gandi.capabilities.recordMutationMode, .recordSetReplacement)
        XCTAssertTrue(DNSProvider.gandi.capabilities.canEdit(recordType: "SVCB"))
        XCTAssertFalse(DNSProvider.gandi.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.goDaddy.capabilities.recordMutationMode, .recordSetReplacement)
        XCTAssertTrue(DNSProvider.goDaddy.capabilities.canEdit(recordType: "SRV"))
        XCTAssertFalse(DNSProvider.goDaddy.capabilities.canEdit(recordType: "NS"))
        XCTAssertEqual(DNSProvider.porkbun.capabilities.recordMutationMode, .individualRecord)
        XCTAssertTrue(DNSProvider.porkbun.capabilities.canEdit(recordType: "HTTPS"))
        XCTAssertFalse(DNSProvider.porkbun.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.nameCom.capabilities.recordMutationMode, .individualRecord)
        XCTAssertTrue(DNSProvider.nameCom.capabilities.canEdit(recordType: "ANAME"))
        XCTAssertFalse(DNSProvider.nameCom.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.spaceship.capabilities.recordMutationMode, .individualRecord)
        XCTAssertTrue(DNSProvider.spaceship.capabilities.canEdit(recordType: "SVCB"))
        XCTAssertFalse(DNSProvider.spaceship.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.ionos.capabilities.recordMutationMode, .individualRecord)
        XCTAssertTrue(DNSProvider.ionos.capabilities.canEdit(recordType: "SMIMEA"))
        XCTAssertFalse(DNSProvider.ionos.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.azureDNS.capabilities.recordMutationMode, .recordSetReplacement)
        XCTAssertTrue(DNSProvider.azureDNS.capabilities.canEdit(recordType: "CAA"))
        XCTAssertFalse(DNSProvider.azureDNS.capabilities.canEdit(recordType: "SOA"))
        XCTAssertTrue(DNSProvider.azureDNS.capabilities.zoneCapabilities.contains(.delete))
        XCTAssertEqual(DNSProvider.oracleCloud.capabilities.recordMutationMode, .recordSetReplacement)
        XCTAssertTrue(DNSProvider.oracleCloud.capabilities.canEdit(recordType: "ALIAS"))
        XCTAssertTrue(DNSProvider.oracleCloud.capabilities.canEdit(recordType: "TLSA"))
        XCTAssertFalse(DNSProvider.oracleCloud.capabilities.canEdit(recordType: "DNSKEY"))
        XCTAssertFalse(DNSProvider.oracleCloud.capabilities.canEdit(recordType: "SOA"))
        XCTAssertTrue(DNSProvider.oracleCloud.capabilities.zoneCapabilities.contains(.delete))
        XCTAssertEqual(DNSProvider.deSEC.capabilities.recordMutationMode, .recordSetReplacement)
        XCTAssertTrue(DNSProvider.deSEC.capabilities.canEdit(recordType: "SVCB"))
        XCTAssertFalse(DNSProvider.deSEC.capabilities.canEdit(recordType: "DNSKEY"))
        XCTAssertTrue(DNSProvider.deSEC.capabilities.zoneCapabilities.contains(.delete))
        XCTAssertEqual(DNSProvider.powerDNS.capabilities.recordMutationMode, .transactionalBatch)
        XCTAssertTrue(DNSProvider.powerDNS.capabilities.canEdit(recordType: "ALIAS"))
        XCTAssertFalse(DNSProvider.powerDNS.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.scaleway.capabilities.recordMutationMode, .transactionalBatch)
        XCTAssertTrue(DNSProvider.scaleway.capabilities.canEdit(recordType: "HTTPS"))
        XCTAssertFalse(DNSProvider.scaleway.capabilities.canEdit(recordType: "SOA"))
        XCTAssertEqual(DNSProvider.ovhCloud.capabilities.recordMutationMode, .individualRecord)
        XCTAssertTrue(DNSProvider.ovhCloud.capabilities.canEdit(recordType: "DKIM"))
        XCTAssertFalse(DNSProvider.ovhCloud.supportsZoneCreation)
        XCTAssertEqual(DNSProvider.ibmNS1.capabilities.recordMutationMode, .recordSetReplacement)
        XCTAssertTrue(DNSProvider.ibmNS1.capabilities.canEdit(recordType: "ALIAS"))
        XCTAssertFalse(DNSProvider.ibmNS1.capabilities.canEdit(recordType: "SOA"))
        XCTAssertTrue(DNSProvider.ibmNS1.capabilities.zoneCapabilities.contains(.delete))
        XCTAssertEqual(DNSProvider.ultraDNS.capabilities.recordMutationMode, .recordSetReplacement)
        XCTAssertTrue(DNSProvider.ultraDNS.capabilities.canEdit(recordType: "APEXALIAS"))
        XCTAssertFalse(DNSProvider.ultraDNS.capabilities.canEdit(recordType: "SOA"))
        XCTAssertFalse(DNSProvider.ultraDNS.supportsZoneCreation)
        XCTAssertEqual(DNSProvider.route53.capabilities.recordMutationMode, .transactionalBatch)
        XCTAssertEqual(DNSProvider.googleCloud.capabilities.recordMutationMode, .transactionalBatch)
        XCTAssertTrue(DNSProvider.vercel.capabilities.canEdit(recordType: "ALIAS"))
        XCTAssertFalse(DNSProvider.vercel.capabilities.canEdit(recordType: "TLSA"))
        XCTAssertTrue(DNSProvider.route53.supportsZoneCreation)
        XCTAssertTrue(DNSProvider.vercel.supportsZoneCreation)
        XCTAssertTrue(DNSProvider.googleCloud.supportsZoneCreation)
    }

    // MARK: - TTL Configuration

    func testDefaultTTL() {
        XCTAssertEqual(DNSProvider.cloudflare.defaultTTL, 1)
        XCTAssertEqual(DNSProvider.digitalOcean.defaultTTL, 1800)
        XCTAssertEqual(DNSProvider.hetzner.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.akamaiCloud.defaultTTL, 300)
        XCTAssertEqual(DNSProvider.vultr.defaultTTL, 300)
        XCTAssertEqual(DNSProvider.dnsimple.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.gandi.defaultTTL, 10800)
        XCTAssertEqual(DNSProvider.goDaddy.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.porkbun.defaultTTL, 600)
        XCTAssertEqual(DNSProvider.nameCom.defaultTTL, 300)
        XCTAssertEqual(DNSProvider.spaceship.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.ionos.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.azureDNS.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.oracleCloud.defaultTTL, 300)
        XCTAssertEqual(DNSProvider.deSEC.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.powerDNS.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.scaleway.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.ovhCloud.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.ibmNS1.defaultTTL, 3600)
        XCTAssertEqual(DNSProvider.ultraDNS.defaultTTL, 300)
        XCTAssertEqual(DNSProvider.route53.defaultTTL, 300)
        XCTAssertEqual(DNSProvider.vercel.defaultTTL, 300)
        XCTAssertEqual(DNSProvider.googleCloud.defaultTTL, 300)
    }

    func testSupportsAutoTTL() {
        XCTAssertTrue(DNSProvider.cloudflare.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.digitalOcean.supportsAutoTTL)
        XCTAssertTrue(DNSProvider.hetzner.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.akamaiCloud.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.vultr.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.dnsimple.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.gandi.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.goDaddy.supportsAutoTTL)
        XCTAssertTrue(DNSProvider.porkbun.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.nameCom.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.spaceship.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.ionos.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.azureDNS.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.oracleCloud.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.deSEC.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.powerDNS.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.scaleway.supportsAutoTTL)
        XCTAssertTrue(DNSProvider.ovhCloud.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.ibmNS1.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.ultraDNS.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.route53.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.vercel.supportsAutoTTL)
        XCTAssertFalse(DNSProvider.googleCloud.supportsAutoTTL)
    }

    func testMinTTL() {
        XCTAssertEqual(DNSProvider.cloudflare.minTTL, 60)
        XCTAssertEqual(DNSProvider.digitalOcean.minTTL, 1)
        XCTAssertEqual(DNSProvider.hetzner.minTTL, 60)
        XCTAssertEqual(DNSProvider.akamaiCloud.minTTL, 300)
        XCTAssertEqual(DNSProvider.vultr.minTTL, 1)
        XCTAssertEqual(DNSProvider.dnsimple.minTTL, 0)
        XCTAssertEqual(DNSProvider.gandi.minTTL, 300)
        XCTAssertEqual(DNSProvider.goDaddy.minTTL, 600)
        XCTAssertEqual(DNSProvider.porkbun.minTTL, 600)
        XCTAssertEqual(DNSProvider.nameCom.minTTL, 300)
        XCTAssertEqual(DNSProvider.spaceship.minTTL, 60)
        XCTAssertEqual(DNSProvider.ionos.minTTL, 300)
        XCTAssertEqual(DNSProvider.azureDNS.minTTL, 1)
        XCTAssertEqual(DNSProvider.oracleCloud.minTTL, 1)
        XCTAssertEqual(DNSProvider.deSEC.minTTL, 1)
        XCTAssertEqual(DNSProvider.powerDNS.minTTL, 0)
        XCTAssertEqual(DNSProvider.scaleway.minTTL, 0)
        XCTAssertEqual(DNSProvider.ovhCloud.minTTL, 60)
        XCTAssertEqual(DNSProvider.ibmNS1.minTTL, 0)
        XCTAssertEqual(DNSProvider.ultraDNS.minTTL, 0)
        XCTAssertEqual(DNSProvider.route53.minTTL, 1)
        XCTAssertEqual(DNSProvider.vercel.minTTL, 60)
        XCTAssertEqual(DNSProvider.googleCloud.minTTL, 1)
    }

    func testMaxTTL() {
        XCTAssertEqual(DNSProvider.cloudflare.maxTTL, 86400)
        XCTAssertEqual(DNSProvider.digitalOcean.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.hetzner.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.akamaiCloud.maxTTL, 2_419_200)
        XCTAssertEqual(DNSProvider.vultr.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.dnsimple.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.gandi.maxTTL, 2_592_000)
        XCTAssertEqual(DNSProvider.goDaddy.maxTTL, 604_800)
        XCTAssertEqual(DNSProvider.porkbun.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.nameCom.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.spaceship.maxTTL, 3600)
        XCTAssertEqual(DNSProvider.ionos.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.azureDNS.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.oracleCloud.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.deSEC.maxTTL, 86400)
        XCTAssertEqual(DNSProvider.powerDNS.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.scaleway.maxTTL, 4_294_967_295)
        XCTAssertEqual(DNSProvider.ovhCloud.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.ibmNS1.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.ultraDNS.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.route53.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.vercel.maxTTL, 2_147_483_647)
        XCTAssertEqual(DNSProvider.googleCloud.maxTTL, 2_147_483_647)
    }

    // MARK: - TTL Normalization

    func testNormalizeTTLNilInput() {
        XCTAssertNil(DNSProvider.cloudflare.normalizeTTL(nil))
        XCTAssertNil(DNSProvider.route53.normalizeTTL(nil))
    }

    func testNormalizeTTLAutomatic() {
        // TTL of 1 means "automatic" in Cloudflare
        XCTAssertEqual(DNSProvider.cloudflare.normalizeTTL(1), 1)
        // TTL of 1 is literal for providers without automatic TTL semantics.
        XCTAssertEqual(DNSProvider.digitalOcean.normalizeTTL(1), 1)
        XCTAssertNil(DNSProvider.hetzner.normalizeTTL(1))
        XCTAssertEqual(DNSProvider.route53.normalizeTTL(1), 1)
        XCTAssertEqual(DNSProvider.vercel.normalizeTTL(1), 60)
        XCTAssertEqual(DNSProvider.googleCloud.normalizeTTL(1), 1)
    }

    func testNormalizeTTLClampsToMin() {
        // Below min for cloudflare (60) should clamp to 60
        XCTAssertEqual(DNSProvider.cloudflare.normalizeTTL(30), 60)
        // Below min for route53 (1) should clamp to 1
        XCTAssertEqual(DNSProvider.route53.normalizeTTL(0), 1)
    }

    func testNormalizeTTLClampsToMax() {
        // Above max for cloudflare (86400)
        XCTAssertEqual(DNSProvider.cloudflare.normalizeTTL(100_000), 86400)
    }

    func testNormalizeTTLWithinRange() {
        XCTAssertEqual(DNSProvider.cloudflare.normalizeTTL(300), 300)
        XCTAssertEqual(DNSProvider.route53.normalizeTTL(3600), 3600)
        XCTAssertEqual(DNSProvider.akamaiCloud.normalizeTTL(301), 3600)
    }

    // MARK: - Effective TTL

    func testGetEffectiveTTLNilReturnsDefault() {
        XCTAssertEqual(DNSProvider.cloudflare.getEffectiveTTL(nil), 1)
        XCTAssertEqual(DNSProvider.digitalOcean.getEffectiveTTL(nil), 1800)
        XCTAssertEqual(DNSProvider.hetzner.getEffectiveTTL(nil), 3600)
        XCTAssertEqual(DNSProvider.akamaiCloud.getEffectiveTTL(nil), 300)
        XCTAssertEqual(DNSProvider.vultr.getEffectiveTTL(nil), 300)
        XCTAssertEqual(DNSProvider.dnsimple.getEffectiveTTL(nil), 3600)
        XCTAssertEqual(DNSProvider.gandi.getEffectiveTTL(nil), 10800)
        XCTAssertEqual(DNSProvider.deSEC.getEffectiveTTL(nil), 3600)
        XCTAssertEqual(DNSProvider.powerDNS.getEffectiveTTL(nil), 3600)
        XCTAssertEqual(DNSProvider.scaleway.getEffectiveTTL(nil), 3600)
        XCTAssertEqual(DNSProvider.ovhCloud.getEffectiveTTL(nil), 3600)
        XCTAssertEqual(DNSProvider.ibmNS1.getEffectiveTTL(nil), 3600)
        XCTAssertEqual(DNSProvider.ultraDNS.getEffectiveTTL(nil), 300)
        XCTAssertEqual(DNSProvider.route53.getEffectiveTTL(nil), 300)
        XCTAssertEqual(DNSProvider.vercel.getEffectiveTTL(nil), 300)
        XCTAssertEqual(DNSProvider.googleCloud.getEffectiveTTL(nil), 300)
    }

    func testGetEffectiveTTLWithValue() {
        XCTAssertEqual(DNSProvider.cloudflare.getEffectiveTTL(300), 300)
        XCTAssertEqual(DNSProvider.route53.getEffectiveTTL(3600), 3600)
    }

    // MARK: - Raw Value

    func testRawValues() {
        XCTAssertEqual(DNSProvider.cloudflare.rawValue, "cloudflare")
        XCTAssertEqual(DNSProvider.digitalOcean.rawValue, "digitalOcean")
        XCTAssertEqual(DNSProvider.hetzner.rawValue, "hetzner")
        XCTAssertEqual(DNSProvider.akamaiCloud.rawValue, "akamaiCloud")
        XCTAssertEqual(DNSProvider.vultr.rawValue, "vultr")
        XCTAssertEqual(DNSProvider.dnsimple.rawValue, "dnsimple")
        XCTAssertEqual(DNSProvider.gandi.rawValue, "gandi")
        XCTAssertEqual(DNSProvider.spaceship.rawValue, "spaceship")
        XCTAssertEqual(DNSProvider.azureDNS.rawValue, "azureDNS")
        XCTAssertEqual(DNSProvider.oracleCloud.rawValue, "oracleCloud")
        XCTAssertEqual(DNSProvider.deSEC.rawValue, "deSEC")
        XCTAssertEqual(DNSProvider.powerDNS.rawValue, "powerDNS")
        XCTAssertEqual(DNSProvider.scaleway.rawValue, "scaleway")
        XCTAssertEqual(DNSProvider.ovhCloud.rawValue, "ovhCloud")
        XCTAssertEqual(DNSProvider.ibmNS1.rawValue, "ibmNS1")
        XCTAssertEqual(DNSProvider.ultraDNS.rawValue, "ultraDNS")
        XCTAssertEqual(DNSProvider.route53.rawValue, "route53")
        XCTAssertEqual(DNSProvider.vercel.rawValue, "vercel")
        XCTAssertEqual(DNSProvider.googleCloud.rawValue, "googleCloud")
    }

    func testInitFromRawValue() {
        XCTAssertEqual(DNSProvider(rawValue: "cloudflare"), .cloudflare)
        XCTAssertEqual(DNSProvider(rawValue: "digitalOcean"), .digitalOcean)
        XCTAssertEqual(DNSProvider(rawValue: "hetzner"), .hetzner)
        XCTAssertEqual(DNSProvider(rawValue: "akamaiCloud"), .akamaiCloud)
        XCTAssertEqual(DNSProvider(rawValue: "vultr"), .vultr)
        XCTAssertEqual(DNSProvider(rawValue: "dnsimple"), .dnsimple)
        XCTAssertEqual(DNSProvider(rawValue: "gandi"), .gandi)
        XCTAssertEqual(DNSProvider(rawValue: "spaceship"), .spaceship)
        XCTAssertEqual(DNSProvider(rawValue: "azureDNS"), .azureDNS)
        XCTAssertEqual(DNSProvider(rawValue: "oracleCloud"), .oracleCloud)
        XCTAssertEqual(DNSProvider(rawValue: "deSEC"), .deSEC)
        XCTAssertEqual(DNSProvider(rawValue: "powerDNS"), .powerDNS)
        XCTAssertEqual(DNSProvider(rawValue: "scaleway"), .scaleway)
        XCTAssertEqual(DNSProvider(rawValue: "ovhCloud"), .ovhCloud)
        XCTAssertEqual(DNSProvider(rawValue: "ibmNS1"), .ibmNS1)
        XCTAssertEqual(DNSProvider(rawValue: "ultraDNS"), .ultraDNS)
        XCTAssertEqual(DNSProvider(rawValue: "route53"), .route53)
        XCTAssertEqual(DNSProvider(rawValue: "vercel"), .vercel)
        XCTAssertEqual(DNSProvider(rawValue: "googleCloud"), .googleCloud)
        XCTAssertNil(DNSProvider(rawValue: "unknown"))
    }

    // MARK: - Setup Links

    func testSetupLinksExist() {
        for provider in DNSProvider.allCases {
            XCTAssertNotNil(provider.setupLink, "\(provider.displayName) should have a setup link")
        }
    }

    func testCloudflareSetupLinkUsesAccountScopedAPITokensRoute() throws {
        let url = try XCTUnwrap(DNSProvider.cloudflare.setupLink?.url)
        XCTAssertEqual(url.absoluteString, "https://dash.cloudflare.com/?to=/:account/api-tokens")
    }
}
