import Foundation

enum ProviderServiceFactory {
    static func makeServices(environmentId: UUID) -> ProviderServiceBundle {
        func credential(_ provider: DNSProvider, _ field: String) -> String? {
            provider.credentialValue(field, environmentId: environmentId)
        }

        let cloudflare = CloudflareService(
            tokenProvider: { credential(.cloudflare, "token") },
            accountIdProvider: { credential(.cloudflare, "accountId") }
        )

        let route53 = Route53Service {
            (
                accessKeyId: credential(.route53, "accessKeyId"),
                secretAccessKey: credential(.route53, "secretAccessKey")
            )
        }

        let digitalOcean = DigitalOceanService(tokenProvider: { credential(.digitalOcean, "token") })
        let hetzner = HetznerService(tokenProvider: { credential(.hetzner, "token") })
        let akamaiCloud = AkamaiCloudService(tokenProvider: { credential(.akamaiCloud, "token") })
        let vultr = VultrService(tokenProvider: { credential(.vultr, "token") })

        let dnsimple = DNSimpleService(
            accountIdProvider: { credential(.dnsimple, "accountId") },
            tokenProvider: { credential(.dnsimple, "token") }
        )

        let gandi = GandiService(tokenProvider: { credential(.gandi, "token") })
        let goDaddy = GoDaddyService {
            (credential(.goDaddy, "token"), credential(.goDaddy, "shopperId"))
        }
        let porkbun = PorkbunService {
            (credential(.porkbun, "apiKey"), credential(.porkbun, "secretApiKey"))
        }
        let nameCom = NameComService {
            (credential(.nameCom, "username"), credential(.nameCom, "token"))
        }
        let namecheap = NamecheapService {
            (
                credential(.namecheap, "username"),
                credential(.namecheap, "apiKey"),
                credential(.namecheap, "clientIp"),
                credential(.namecheap, "environment")
            )
        }
        let spaceship = SpaceshipService {
            (credential(.spaceship, "apiKey"), credential(.spaceship, "apiSecret"))
        }
        let ionos = IONOSService(apiKeyProvider: { credential(.ionos, "apiKey") })

        let azureDNS = AzureDNSService(credentialsProvider: {
            (
                tenantId: credential(.azureDNS, "tenantId"),
                clientId: credential(.azureDNS, "clientId"),
                clientSecret: credential(.azureDNS, "clientSecret"),
                subscriptionId: credential(.azureDNS, "subscriptionId"),
                resourceGroup: credential(.azureDNS, "resourceGroup")
            )
        })

        let oracleCloud = OracleCloudDNSService(credentialsProvider: {
            (
                tenancyId: credential(.oracleCloud, "tenancyId"),
                userId: credential(.oracleCloud, "userId"),
                fingerprint: credential(.oracleCloud, "fingerprint"),
                privateKeyPEM: credential(.oracleCloud, "privateKeyPEM"),
                region: credential(.oracleCloud, "region"),
                compartmentId: credential(.oracleCloud, "compartmentId"),
                realmDomain: credential(.oracleCloud, "realmDomain")
            )
        })

        let deSEC = DeSECService(tokenProvider: { credential(.deSEC, "token") })

        let powerDNS = PowerDNSService(credentialsProvider: {
            (
                endpoint: credential(.powerDNS, "endpoint"),
                apiKey: credential(.powerDNS, "apiKey"),
                serverId: credential(.powerDNS, "serverId"),
                nameserver: credential(.powerDNS, "nameserver")
            )
        })

        let scaleway = ScalewayService(credentialsProvider: {
            (
                secretKey: credential(.scaleway, "secretKey"),
                projectId: credential(.scaleway, "projectId")
            )
        })

        let ovhCloud = OVHCloudService(credentialsProvider: {
            (
                endpoint: credential(.ovhCloud, "endpoint"),
                applicationKey: credential(.ovhCloud, "applicationKey"),
                applicationSecret: credential(.ovhCloud, "applicationSecret"),
                consumerKey: credential(.ovhCloud, "consumerKey")
            )
        })

        let ibmNS1 = IBMNS1Service(apiKeyProvider: { credential(.ibmNS1, "apiKey") })
        let ultraDNS = UltraDNSService {
            (credential(.ultraDNS, "username"), credential(.ultraDNS, "password"))
        }

        let vercel = VercelService(
            tokenProvider: { credential(.vercel, "token") },
            teamIdProvider: { credential(.vercel, "teamId") }
        )

        let googleCloud = GoogleCloudService(
            credentialsProvider: { credential(.googleCloud, "serviceAccountJSON") },
            projectIdProvider: { credential(.googleCloud, "projectId") }
        )

        return ProviderServiceRegistry([
            CloudflareDNSProviderService(service: cloudflare),
            DigitalOceanDNSProviderService(service: digitalOcean),
            HetznerDNSProviderService(service: hetzner),
            AkamaiCloudDNSProviderService(service: akamaiCloud),
            VultrDNSProviderService(service: vultr),
            DNSimpleDNSProviderService(service: dnsimple),
            GandiDNSProviderService(service: gandi),
            GoDaddyDNSProviderService(service: goDaddy),
            PorkbunDNSProviderService(service: porkbun),
            NameComDNSProviderService(service: nameCom),
            NamecheapDNSProviderService(service: namecheap),
            SpaceshipDNSProviderService(service: spaceship),
            IONOSDNSProviderService(service: ionos),
            AzureDNSProviderService(service: azureDNS),
            OracleCloudDNSProviderService(service: oracleCloud),
            DeSECDNSProviderService(service: deSEC),
            PowerDNSDNSProviderService(service: powerDNS),
            ScalewayDNSProviderService(service: scaleway),
            OVHCloudDNSProviderService(service: ovhCloud),
            IBMNS1DNSProviderService(service: ibmNS1),
            UltraDNSProviderService(service: ultraDNS),
            Route53DNSProviderService(service: route53),
            VercelDNSProviderService(service: vercel),
            GoogleCloudDNSProviderService(service: googleCloud),
        ])
    }
}
