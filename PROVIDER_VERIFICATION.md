# Provider Verification Ledger

> Historical evidence recovered with the pre-React-Native SwiftUI source.
> Dates and results below describe the original implementation work. They do
> not establish current live API compatibility or release readiness. Current
> restoration checks are recorded in RESTORATION.md.

This ledger records the contract and end-to-end evidence used for DNSDeck
provider integrations. Every provider must pass provider-registry validation,
formatting, and Release builds for macOS and the iOS Simulator before its
commit. Cloudflare, GoDaddy, Amazon Route 53, and IONOS additionally require
their signed provider XCUITest journeys.

## Verification method

1. Treat the provider's current API reference as the primary contract.
2. Cross-check request shapes and edge cases against an official SDK or CLI when available.
3. Review a mature independent DNS implementation and relevant open issues for operational behavior omitted from the API reference.
4. For the four mandatory UI-test providers, exercise user-visible authentication and supported flows through an isolated live fixture.
5. Preserve provider-native data or block mutations when a provider's write contract cannot safely round-trip it.

Live credentials remain outside the repository and are loaded only by explicit
provider-specific test targets.

## Mandatory UI-test scope

The signed `ProviderCanaries` target contains only Cloudflare, GoDaddy, Amazon
Route 53, and IONOS. All four journeys are mandatory and run without a provider
selection or skip filter. Other provider integrations rely on contract,
registry, formatting, and build validation rather than retained UI tests.

## Shared foundation

- Provider definitions declare credentials, zone capabilities, record mutation semantics, features, editable record types, and TTL behavior.
- The credential store supports arbitrary required and optional fields while preserving existing keychain keys.
- Provider operations dispatch through a registry and type-erased service boundary.
- Network transports are injectable. New REST integrations use bounded retries only for read operations and reject pagination URLs outside their configured API origin.
- Generic zone and record snapshots preserve provider-native JSON, multi-value RRsets, aliases, routing policy, metadata, and ETags.
- Zone creation and safe provider-supported zone deletion are capability-gated.

## Registrar nameserver delegation audit

Status: implemented and fixture-verified on 2026-07-13.

This capability means changing the nameserver set published by the parent registry for a registered domain. It does not mean editing an apex `NS` RRset, changing a secondary zone's upstream masters, or displaying a DNS host's assigned nameservers. DNSDeck shows **Update Nameservers** only for providers with a documented write API that can affect registrar delegation for at least their internally registered domains.

| Provider              | DNSDeck action | Official contract and decision                                                                                                                                                                                                                           |
| --------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cloudflare            | Not exposed    | [Cloudflare Registrar domains must use Cloudflare nameservers](https://developers.cloudflare.com/registrar/get-started/transfer-domain-to-cloudflare/). Zone custom nameservers are a plan-gated vanity feature, not a general registrar delegation API. |
| DigitalOcean          | Not exposed    | [Domains API](https://docs.digitalocean.com/reference/api/reference/domains/) manages hosted DNS; delegation is changed at the registrar.                                                                                                                |
| Hetzner               | Not exposed    | [`change_primary_nameservers`](https://docs.hetzner.cloud/reference/cloud#zone-actions-change-the-primary-nameservers-of-a-zone) changes upstream masters for a secondary zone, not parent delegation.                                                   |
| Akamai Cloud / Linode | Not exposed    | [Create domain](https://techdocs.akamai.com/linode-api/reference/post-domain) requires users to point the registrar to Linode separately.                                                                                                                |
| Vultr                 | Not exposed    | [Vultr nameserver guide](https://docs.vultr.com/products/network/dns/point-to-vultr-name-servers) directs users to update their registrar.                                                                                                               |
| DNSimple              | Exposed        | [`PUT /registrar/domains/:domain/delegation`](https://developer.dnsimple.com/v2/registrar/delegation/) replaces registry nameservers.                                                                                                                    |
| Gandi LiveDNS         | Not exposed    | [LiveDNS nameserver API](https://api.gandi.net/docs/livedns/) reads the nameservers derived from hosted-zone configuration; it does not change registrar delegation.                                                                                     |
| GoDaddy               | Exposed        | [Domains Swagger](https://developer.godaddy.com/swagger/swagger_domains.json) defines `PATCH /v1/domains/{domain}` with `nameServers`.                                                                                                                   |
| Porkbun               | Exposed        | [Public OpenAPI](https://porkbun.com/api/json/v3/spec) defines `POST /domain/updateNs/{domain}`.                                                                                                                                                         |
| Name.com              | Exposed        | [`domains/{domain}:setNameservers`](https://docs.name.com/api/v1/reference/domains/set-nameservers) replaces registrar nameservers.                                                                                                                      |
| Namecheap             | Exposed        | [`namecheap.domains.dns.setCustom`](https://www.namecheap.com/support/api/methods/domains-dns/set-custom/) replaces nameservers for a Namecheap-registered domain.                                                                                       |
| Spaceship             | Exposed        | [Public API](https://docs.spaceship.dev/) defines `PUT /v1/domains/{domain}/nameservers`; keys require `domains:write`.                                                                                                                                  |
| IONOS                 | Not exposed    | The [Hosting DNS API](https://developer.hosting.ionos.com/docs/dns) manages zones and records only; custom registrar nameservers remain a control-panel operation.                                                                                       |
| Azure DNS             | Not exposed    | [`nameServers` is read-only](https://learn.microsoft.com/en-us/rest/api/dns/zones/create-or-update?view=rest-dns-2018-05-01) on managed zones.                                                                                                           |
| Oracle Cloud DNS      | Not exposed    | [Zone management](https://docs.oracle.com/en-us/iaas/Content/DNS/Tasks/managingdnszones.htm) can change external masters for secondary zones, not registrar delegation.                                                                                  |
| deSEC                 | Not exposed    | [Domain fields](https://desec.readthedocs.io/en/latest/dns/domains.html) make apex nameservers provider-managed and direct delegation changes to the registrar.                                                                                          |
| PowerDNS              | Not exposed    | [Zone API](https://doc.powerdns.com/authoritative/http-api/zone.html) changes authoritative zone content only.                                                                                                                                           |
| Scaleway              | Exposed        | [Domains and DNS API/CLI](https://cli.scaleway.com/dns/) defines `PUT /dns-zones/{dns_zone}/nameservers`; DNSDeck limits it to writable root zones. External-domain registry delegation may still require the external registrar.                        |
| OVHcloud              | Exposed        | [Domain nameserver API guide](https://help.ovhcloud.com/csm/en-sg-domain-names-api-dns?id=kb_article_view&sysparm_article=KB0051527) defines `POST /domain/{serviceName}/nameServers/update` for OVH-registered domains using external nameservers.      |
| IBM NS1 Connect       | Not exposed    | [Delegation guide](https://www.ibm.com/docs/en/ns1-connect?topic=nameservers-delegating-domain-ns1-connect) directs primary-zone users to their registrar.                                                                                               |
| UltraDNS              | Not exposed    | The [Zone API](https://docs.ultradns.com/Content/REST%20API/Content/REST%20API/Zone%20API/Zone%20API.htm) manages hosted zones and registrar information is read-only.                                                                                   |
| Amazon Route 53       | Exposed        | [Route 53 Domains `UpdateDomainNameservers`](https://docs.aws.amazon.com/Route53/latest/APIReference/API_domains_UpdateDomainNameservers.html) replaces nameservers for domains registered in the AWS account and returns an asynchronous operation ID.  |
| Vercel                | Exposed        | [Registrar API](https://vercel.com/docs/domains/registrar-api) defines `PATCH /v1/registrar/domains/{domain}/nameservers` for Vercel-registered domains.                                                                                                 |
| Google Cloud          | Exposed        | [Cloud Domains `configureDnsSettings`](https://cloud.google.com/domains/docs/reference/rest/v1/projects.locations.registrations/configureDnsSettings) updates registration nameservers; DNSDeck preserves existing custom-DNS DS records.                |

Shared implementation decisions:

- Hostnames are trimmed, lowercased, stripped of a trailing dot, validated label-by-label, and rejected if duplicated. DNSDeck requires 2 through 12 nameservers, matching the strictest documented provider contract in this set.
- Provider capability declarations control context-menu visibility. Each service adapter still validates native zone data and lets the provider reject zones that are hosted but not registered in the same account.
- Registry writes are never represented as apex `NS` record edits. Providers with asynchronous registrar workflows return after the documented API accepts the operation; later registry propagation remains provider-controlled.
- Google Cloud reads the current registration before writing so an existing custom-DNS DS set is not silently discarded. Route 53 signs the registrar request for the distinct `route53domains` service in `us-east-1`.

## DigitalOcean

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [DigitalOcean Domains API](https://docs.digitalocean.com/reference/api/reference/domains/)
- [DigitalOcean Domain Records API](https://docs.digitalocean.com/products/networking/dns/reference/api/domain-records/)
- [DigitalOcean API conventions, pagination, and rate limits](https://docs.digitalocean.com/reference/api/reference/public-apis/)
- [Official `godo` domains implementation](https://github.com/digitalocean/godo/blob/master/domains.go)
- [Official `doctl` CLI](https://github.com/digitalocean/doctl)

Independent and issue evidence:

- [DNSControl DigitalOcean provider](https://github.com/StackExchange/dnscontrol/tree/master/providers/digitalocean)
- [Terraform provider DNS record implementation](https://github.com/digitalocean/terraform-provider-digitalocean/blob/main/digitalocean/domain/resource_record.go)
- [Open Terraform provider issue #1539: imported record TTL warning](https://github.com/digitalocean/terraform-provider-digitalocean/issues/1539)
- [DNSControl issue #370: DigitalOcean TXT record length behavior](https://github.com/StackExchange/dnscontrol/issues/370)

Implementation decisions:

- Bearer authentication uses a single token with least-privilege `domain:read`, `domain:create`, `domain:update`, and `domain:delete` scopes as needed.
- List operations request 200 items and follow only same-origin HTTPS `links.pages.next` URLs, with cycle and page-count bounds.
- Transient retries are bounded and limited to reads. `Retry-After` is honored with a maximum wait bound.
- Zone creation, details, deletion, record listing, and individual record create/update/delete match the documented `/v2/domains` contracts.
- A, AAAA, CAA, CNAME, MX, NS, SRV, and TXT are editable. SOA is preserved as read-only because the API only permits a partial SOA update.
- SRV `priority`, `weight`, `port`, and target and CAA `flags`, `tag`, and value are preserved independently in native JSON.
- DNSDeck surfaces DigitalOcean's behavior that records in one RRset may be normalized to a shared TTL. TXT values are not pre-truncated; API validation errors remain visible to the user.

## Hetzner

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Current Hetzner Cloud API reference](https://docs.hetzner.cloud/reference/cloud)
- [Machine-readable Hetzner Cloud OpenAPI specification](https://docs.hetzner.cloud/cloud.spec.json)
- [Official `hcloud-go` zone client](https://github.com/hetznercloud/hcloud-go/blob/main/hcloud/zone.go)
- [Official `hcloud-go` RRSet client](https://github.com/hetznercloud/hcloud-go/blob/main/hcloud/zone_rrset.go)
- [Official `hcloud` zone CLI](https://github.com/hetznercloud/cli/tree/main/internal/cmd/zone)
- [Hetzner Cloud API changelog](https://docs.hetzner.cloud/changelog)

Issue evidence:

- Searches of the official [`hcloud-go` issues](https://github.com/hetznercloud/hcloud-go/issues?q=is%3Aissue+zone) and [`hcloud` CLI issues](https://github.com/hetznercloud/cli/issues?q=is%3Aissue+DNS+zone) found no open issue specific to the generally available Cloud DNS endpoints at verification time.

Implementation decisions:

- DNSDeck uses `https://api.hetzner.cloud/v1`, which became the generally available DNS API in November 2025. It does not use the retired `dns.hetzner.com` API.
- Project-bound bearer tokens support browsing with read-only access; mutations require a read-write token.
- Zone and RRSet listings follow integer `meta.pagination.next_page` values with the official 50-item SDK page size.
- All asynchronous write actions are polled through `/v1/actions/{id}` to `success` or `error`. Record updates and deletions additionally require three consecutive matching reads from the paginated RRSet collection before refresh, preventing a successful write from being replaced in the UI by a briefly stale list response. Polling is bounded and action errors retain their action ID, code, and message.
- Newly created zones are reloaded after their action completes because assigned authoritative nameservers are populated asynchronously, matching the official CLI behavior.
- RRSets are represented as one DNSDeck record with all values preserved. Create, set-records, TTL inheritance/change, rename-by-create-then-delete, and delete match the current RRSet contracts.
- A, AAAA, CAA, CNAME, DS, HINFO, HTTPS, MX, NS, PTR, RP, SRV, SVCB, TLSA, and TXT are editable. SOA is preserved read-only because Hetzner automatically maintains its serial.
- Explicit RRSet TTLs are limited to 60 through 2147483647 seconds. Automatic means inheriting the zone's default TTL.
- TXT values are quoted, escaped, and split into at most 255-byte strings on write, then presented unquoted in DNSDeck. Native quoted values and per-record comments remain preserved in opaque provider data.

## Akamai Cloud (Linode)

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Linode API v4 reference](https://techdocs.akamai.com/linode-api/reference/api)
- [Official Linode OpenAPI repository](https://github.com/linode/linode-api-openapi)
- [Create a domain record reference](https://techdocs.akamai.com/linode-api/reference/post-domain-record)
- [Official `linodego` domain implementation](https://github.com/linode/linodego/blob/main/domains.go)
- [Official `linodego` domain-record implementation](https://github.com/linode/linodego/blob/main/domain_records.go)
- [Akamai Cloud DNS Manager documentation](https://techdocs.akamai.com/cloud-computing/docs/dns-manager)

Issue evidence:

- [Terraform provider issue #1082: record-name normalization drift](https://github.com/linode/terraform-provider-linode/issues/1082)
- [Terraform provider issue #572: CNAME target normalization drift](https://github.com/linode/terraform-provider-linode/issues/572)
- [Terraform provider issue #484: 30/120 second TTL discrepancy](https://github.com/linode/terraform-provider-linode/issues/484)
- [Terraform provider issue #222: rate limiting during bulk DNS writes](https://github.com/linode/terraform-provider-linode/issues/222)
- [Terraform provider issue #87: SRV service/name normalization drift](https://github.com/linode/terraform-provider-linode/issues/87)

Implementation decisions:

- DNSDeck uses the stable Linode API v4 with a personal access token carrying `domains:read_only` or `domains:read_write` scope.
- List endpoints use the documented 500-item maximum page size and bounded page-number traversal.
- Domain creation provisions an active primary (`master`) zone with `hostmaster@<domain>` as its SOA email and the documented 24-hour domain default TTL. Secondary (`slave`) zones remain browsable but record mutations are rejected locally as read-only.
- The five authoritative nameservers are `ns1.linode.com` through `ns5.linode.com`, as listed in the current DNS Manager guide.
- A, AAAA, CAA, CNAME, MX, NS, PTR, SRV, and TXT use individual-record CRUD. The native record payload is preserved on every snapshot.
- Linode's separate SRV `service`, `protocol`, `priority`, `weight`, `port`, and target fields are round-tripped without underscore drift. CAA tags and the provider's fixed flags value of 0 are validated explicitly.
- Record TTL input is normalized upward to the current API reference allowlist: 300, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 345600, 604800, 1209600, or 2419200 seconds. The older 30/120 discrepancy is retained in the issue ledger rather than relying on undocumented behavior.
- Read-only requests have bounded transient retries. Writes are not automatically retried, avoiding duplicate records under ambiguous 429 or network failures.
- DNS Manager currently requires at least one active Linode for zones to be served and does not support DNSSEC; both constraints are surfaced in provider documentation and the verification ledger.

## Vultr

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Vultr API v2 DNS reference](https://www.vultr.com/api/#tag/dns)
- [Vultr DNS provisioning guide](https://docs.vultr.com/products/network/dns/provisioning)
- [Official `govultr` domain implementation](https://github.com/vultr/govultr/blob/master/domains.go)
- [Official `govultr` domain-record implementation](https://github.com/vultr/govultr/blob/master/domain_records.go)
- [Official Terraform DNS-record implementation](https://github.com/vultr/terraform-provider-vultr/blob/master/vultr/resource_vultr_dns_records.go)
- [`libdns/vultr` record conversion implementation](https://github.com/libdns/vultr/blob/master/helpers.go)

Issue evidence:

- [Terraform provider issue #105: empty apex record names must not be omitted](https://github.com/vultr/terraform-provider-vultr/issues/105)
- [`caddy-dns/vultr` issue #8: provider breakage after record-model changes](https://github.com/caddy-dns/vultr/issues/8)

Implementation decisions:

- DNSDeck uses Vultr API v2 with bearer API-key authentication and the documented 500-item maximum cursor page size.
- Domain list, details, create, and delete are supported. New domains omit the optional default IP and DNSSEC fields so Vultr creates an empty zone without an implicit A record.
- Vultr's authoritative nameservers `ns1.vultr.com` and `ns2.vultr.com` are surfaced on zone snapshots.
- A, AAAA, CAA, CNAME, MX, NS, SRV, SSHFP, and TXT use individual-record CRUD. Updates use `PATCH`; record type changes are rejected because that endpoint does not accept `type`.
- Apex names are encoded as the required empty string rather than omitted, directly covering the official provider regression in issue #105.
- Vultr stores MX/SRV priority separately. DNSDeck reconstructs standard display content and writes SRV data as weight, port, and target while preserving priority in its native field.
- Native zone and record payloads are retained in snapshots. Read requests have bounded transient retries, while writes are never retried automatically.

## DNSimple

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [DNSimple API v2 overview](https://developer.dnsimple.com/v2/)
- [Official OpenAPI v3 YAML](https://developer.dnsimple.com/v2/openapi.yml)
- [Official OpenAPI v3 JSON](https://developer.dnsimple.com/v2/openapi.json)
- [Zone Records API](https://developer.dnsimple.com/v2/zones/records/)
- [Official `dnsimple-go` zone implementation](https://github.com/dnsimple/dnsimple-go/blob/main/dnsimple/zones.go)
- [Official `dnsimple-go` zone-record implementation](https://github.com/dnsimple/dnsimple-go/blob/main/dnsimple/zones_records.go)
- [Supported DNS record types](https://support.dnsimple.com/articles/supported-dns-records/)

Issue evidence:

- [Terraform provider issue #360: priority is valid only for MX and SRV](https://github.com/dnsimple/terraform-provider-dnsimple/issues/360)
- [Terraform provider issue #315: implicit integrated-zone propagation can affect Azure](https://github.com/dnsimple/terraform-provider-dnsimple/issues/315)
- [Terraform provider issue #210: rate limiting on large accounts](https://github.com/dnsimple/terraform-provider-dnsimple/issues/210)
- [Terraform provider issue #356: zone-level authoritative NS records use a separate API](https://github.com/dnsimple/terraform-provider-dnsimple/issues/356)

Implementation decisions:

- DNSDeck uses DNSimple API v2 with bearer account-token authentication and an explicit numeric account ID, as every zone path is account-scoped.
- Zone list and details use the documented 100-item maximum page size. DNSimple has activation/deactivation rather than zone create/delete endpoints, so DNSDeck does not misrepresent domain or service lifecycle operations as zone CRUD.
- Standard primary zones surface `ns1.dnsimple.com` through `ns4.dnsimple.com`. Secondary zones remain browsable but are locally read-only.
- A, AAAA, ALIAS, CAA, CNAME, HINFO, MX, NAPTR, NS, POOL, PTR, SPF, SRV, SSHFP, TXT, and URL follow the current OpenAPI record contract. System records and generated child records are retained but rejected locally for mutation.
- MX and SRV priority is sent only in the dedicated priority field. SRV display content is reconstructed without losing weight, port, or target; non-priority record types never receive a priority field.
- Create and update payloads explicitly set `integrated_zones` to `dnsimple`, preventing DNSDeck writes from implicitly propagating into third-party integrated zones. This follows the API prose contract; the current OpenAPI item schema still documents integer IDs and is tracked as contract drift.
- Native zones, records, region lists, system flags, and parent relationships are preserved in opaque snapshots. Reads retry bounded transient failures; writes do not retry automatically.

## Gandi LiveDNS

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Gandi LiveDNS v5 API reference](https://api.gandi.net/docs/livedns/)
- [Gandi v5 authentication reference](https://api.gandi.net/docs/authentication/)
- [Gandi Public API changelog](https://api.gandi.net/docs/changelog/)
- [Personal Access Token guide](https://docs.gandi.net/en/managing_an_organization/organizations/personal_access_token.html)
- [`go-gandi` LiveDNS domain-record implementation](https://github.com/go-gandi/go-gandi/blob/master/livedns/domainrecord.go)
- [`go-gandi` LiveDNS models](https://github.com/go-gandi/go-gandi/blob/master/livedns/types.go)
- [Terraform LiveDNS RRset implementation](https://github.com/go-gandi/terraform-provider-gandi/blob/master/gandi/resource_livedns_record.go)

Contract note:

- Gandi publishes the current LiveDNS schema as rendered RAML documentation rather than a downloadable OpenAPI document. The transport fixtures mirror that official RAML contract, including RRset arrays, response headers, integer error codes, and the 2025 PATCH addition.

Issue evidence:

- [Terraform provider issue #147: PATs require Bearer rather than deprecated Apikey auth](https://github.com/go-gandi/terraform-provider-gandi/issues/147)
- [Terraform provider issue #126: existing MX RRsets conflict with duplicate creation](https://github.com/go-gandi/terraform-provider-gandi/issues/126)
- [Terraform provider issue #41: long TXT chunk normalization causes perpetual drift](https://github.com/go-gandi/terraform-provider-gandi/issues/41)
- [Terraform provider issue #89: zone and record TTL semantics must not be conflated](https://github.com/go-gandi/terraform-provider-gandi/issues/89)

Implementation decisions:

- DNSDeck accepts only scoped Personal Access Tokens and sends `Authorization: Bearer`; the deprecated `Apikey` scheme is intentionally not exposed.
- Domain list, details, and creation are supported. The current LiveDNS API does not provide domain deletion, so DNSDeck does not map the destructive delete-all-records endpoint to zone deletion.
- Domain and RRset collection endpoints use bounded page traversal and the `Total-Count` response header. Domain details fetch the authenticated nameserver endpoint because Gandi assigns domain-specific hashed nameservers or returns custom apex NS records.
- Records are modeled as multi-value RRSets. Same-name/type updates use full-set `PUT`; rename/type changes create the new set before deleting the old one and attempt rollback if deletion fails.
- TTLs are constrained to the documented 300 through 2592000 seconds. The SOA TTL used during domain creation is not treated as a record default.
- Long TXT values are quoted and split into DNS-safe 255-byte character strings on write, then recombined for display while preserving the exact native RRset for unchanged updates.
- A, AAAA, ALIAS, CAA, CDS, CNAME, DNAME, DS, HTTPS, KEY, LOC, MX, NAPTR, NS, OPENPGPKEY, PTR, RP, SPF, SRV, SSHFP, SVCB, TLSA, TXT, and WKS follow the current LiveDNS contract. SOA remains provider-managed and read-only.
- Read requests use bounded transient retries. No write, including idempotent-looking RRset replacement, is retried automatically after an ambiguous transport failure.

## GoDaddy

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [GoDaddy Domains API reference](https://developer.godaddy.com/doc/endpoint/domains)
- [Current GoDaddy Domains Swagger 2.0 specification](https://developer.godaddy.com/swagger/swagger_domains.json)
- [GoDaddy API authentication and access guide](https://developer.godaddy.com/getstarted)
- [April 2026 DNS API eligibility announcement](https://www.godaddy.com/resources/news/godaddy-dns-api-now-works-with-a-single-domain)
- [GoDaddy domain API access limits](https://www.godaddy.com/help/how-do-i-access-domain-related-apis-42424)
- [GoDaddy DNS TTL guidance](https://www.godaddy.com/resources/skills/how-to-check-dns-and-diagnose-common-issues)
- [GoDaddy API Terms of Use](https://developer.godaddy.com/getstarted)

Client and issue evidence:

- GoDaddy publishes its machine-readable Swagger contract but no maintained first-party general-purpose client SDK. The integration was therefore cross-checked against the mature [`go-acme/lego` GoDaddy client](https://github.com/go-acme/lego/tree/master/providers/dns/godaddy) and [`terraform-provider-godaddy-dns`](https://github.com/veksh/terraform-provider-godaddy-dns/tree/main/internal/client).
- [`certbot-dns-godaddy` issue #82: the 2024 portfolio-size access regression](https://github.com/miigotu/certbot-dns-godaddy/issues/82)
- [`go-acme/lego` issue #2269: type/name RRset replacement and collection-path behavior](https://github.com/go-acme/lego/issues/2269)
- [DNSControl issue #2596: target normalization and trailing-dot behavior](https://github.com/DNSControl/dnscontrol/issues/2596)

Implementation decisions:

- DNSDeck uses production key/secret credentials with `Authorization: sso-key <key>:<secret>`. Optional `X-Shopper-Id` is available only for GoDaddy's documented reseller subaccount flow. The app does not create keys or call purchase, transfer, renewal, or domain-cancellation endpoints.
- The April 2026 policy now grants Domains API access to accounts with one active domain. DNSDeck lists only active domains, includes nameservers, and traverses the documented 1,000-domain marker pages with cycle and page-count bounds.
- DNS records use the documented collection GET with 500-record offset pages. The current Swagger models the operation under the optional type/name path even though the live collection path omits both segments; this known schema/path mismatch is covered directly by transport fixtures.
- A, AAAA, CNAME, MX, SRV, and TXT are editable. NS and SOA are retained as provider-native read-only records because the type/name delete endpoint explicitly excludes them and registrar-managed apex data must not be removed through a record editor.
- Creates use the additive collection `PATCH`. Updates replace the complete matching type/name set with `PUT`, and deletes remove that complete set. SRV records are grouped by service and protocol for display; every write first preserves sibling SRV services that share GoDaddy's broader native type/name replacement boundary.
- Rename and type changes check for destination conflicts, create the destination before removing the source, and restore the exact prior destination state if source removal fails. No write is retried automatically.
- MX priority and GoDaddy's separate SRV service, protocol, priority, weight, port, and target fields are retained in native snapshots. TTL defaults to one hour and is normalized to GoDaddy's 600-second minimum and one-week API range.
- The 2024 access failures remain in the issue ledger because existing API keys may still surface stale 403 behavior. Current official access policy and April 2026 primary-source announcement take precedence over those older reports.

## Porkbun

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Porkbun API v3.8 documentation](https://porkbun.com/api/json/v3/documentation)
- [Official OpenAPI 3.0 specification](https://porkbun.com/api/json/v3/spec)
- [Official DNS reference in Markdown](https://porkbun.com/llms/dns)
- [Official Porkbun MCP server and API client](https://github.com/oborseth/Porkbun-MCP)
- [Porkbun API setup and 2025 hostname migration](https://kb.porkbun.com/article/190-getting-started-with-the-porkbun-api)
- [Current DNS record behavior and type guidance](https://kb.porkbun.com/article/231-how-to-add-dns-records-on-porkbun)
- [Porkbun 600-second minimum TTL guidance](https://kb.porkbun.com/article/33-how-long-will-it-take-for-changes-to-dns-to-show-up)

Issue evidence:

- [DNSControl issue #3016: domain flags changed between strings and numbers](https://github.com/DNSControl/dnscontrol/issues/3016)
- [DNSControl issue #3225: burst rate limits returned non-JSON 503 responses](https://github.com/DNSControl/dnscontrol/issues/3225)
- [DNSControl issue #3741: high-concurrency failures across many domains](https://github.com/DNSControl/dnscontrol/issues/3741)
- [`go-acme/lego` issue #2391: migration away from the legacy `porkbun.com` API hostname](https://github.com/go-acme/lego/issues/2391)
- [DNSControl issue #3199: historical CAA support gap](https://github.com/DNSControl/dnscontrol/issues/3199)

Implementation decisions:

- DNSDeck uses the current `https://api.porkbun.com/api/json/v3` origin, not the retired website hostname. Read operations use the new GET forms with `X-API-Key` and `X-Secret-API-Key`; writes mirror the official MCP client by keeping credentials in the JSON body, which DNSDeck never logs.
- Domain listing filters to `apiAccess=yes`, uses stable domain ordering, and traverses the documented 1,000-domain `start` offsets with cycle and page-count bounds. Domain details and registry nameservers use the new single-domain and GET nameserver endpoints.
- Domain status flags decode from either strings or numbers, directly covering the response drift in issue #3016. Every provider-native domain and record payload is retained in opaque snapshot data.
- A, AAAA, ALIAS, CAA, CNAME, HTTPS, MX, NS, SRV, SSHFP, SVCB, TLSA, and TXT use individual record-ID create/edit/delete. The API excludes SOA and Porkbun's default NS records from record retrieval; user-created subdomain NS records remain editable.
- MX and SRV priority remain in the dedicated `prio` field. SRV content is normalized to Porkbun's weight, port, and target string while retaining priority separately. Optional record notes map to DNSDeck comments.
- Apex record writes use Porkbun's documented blank name. Automatic TTL sends zero so Porkbun applies the account minimum; explicit values are bounded to the documented 600-second minimum.
- Every POST receives one UUID idempotency key that remains stable across bounded retries. This permits safe retry of transient 429/5xx and transport failures under Porkbun's 24-hour replay contract without duplicating record creation. Reads also use bounded transient retries and honor `Retry-After`; no request is fanned out concurrently across domains.
- HTTP errors and legacy HTTP-200 `status: ERROR` envelopes retain machine codes, request IDs, and `next_action` remediation hints. Current OpenAPI support for CAA supersedes the older issue #3199 report, which remains recorded as historical contract drift.

## Name.com

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Name.com Core API overview](https://docs.name.com/api/v1/overview)
- [Current Core API OpenAPI 3.1 YAML](https://namedotcom-cdn.name.tools/api-info/namecom.api.yaml)
- [Core DNS record reference](https://docs.name.com/api/v1/reference/dns/list-records)
- [v4-to-Core migration guide](https://docs.name.com/guides/migration-guide)
- [Official sandbox guide](https://docs.name.com/guides/testing-environment)
- [Core API changelog](https://docs.name.com/api/v1/changelog)
- [Official Name.com MCP server and API client](https://github.com/namedotcom/namecom-mcp)
- [API token setup guide](https://cs.name.com/hc/en-us/articles/360007597874-Signing-up-for-API-access)

Issue evidence:

- [Traefik issue #12059: a stale embedded `/v4` base path broke Name.com DNS calls](https://github.com/traefik/traefik/issues/12059)
- [`go-acme/lego` issue #656: authoritative DNS propagation required much longer polling](https://github.com/go-acme/lego/issues/656)
- [DNSControl issue #343: a generated legacy client produced invalid domain updates](https://github.com/DNSControl/dnscontrol/issues/343)

Implementation decisions:

- DNSDeck targets the current `https://api.name.com/core/v1` contract released in June 2025. It does not use the legacy v4 client or embed `/v4` in the configurable origin; Name.com has announced that v4 will sunset in 2026.
- Authentication is HTTP Basic using the account username and API token, matching both OpenAPI 1.29.3 and the official MCP client. The provider setup text surfaces the current documented incompatibility with two-step-verification accounts.
- Domain and record collections request the OpenAPI maximum of 1,000 items and follow bounded, cycle-checked `nextPage` values. The separate `api.dev.name.com` sandbox and `-test` credentials were used as contract evidence, but fixtures do not require any account.
- Domain registration is not represented as DNS zone creation or deletion. Existing domains are listed and reloaded for their assigned nameservers without exposing registrar purchase, renewal, or transfer operations.
- A, AAAA, ANAME, CNAME, MX, NS, SRV, and TXT use individual record-ID create, full-overwrite update, and delete operations. Every `PUT` includes host, type, answer, TTL, and priority where applicable, even when DNSDeck changes only one field.
- Apex names are encoded as an empty host. ANAME targets map to alias metadata. MX priority remains separate, and SRV values round-trip as the provider's documented priority plus `weight port target` answer.
- Explicit TTLs are bounded to Name.com's documented 300-second minimum. Provider-native domain and record payloads are retained in opaque snapshots.
- Reads have bounded transient retries and honor both `Retry-After` and Name.com's epoch-valued `X-RateLimit-Reset`. Writes are never retried automatically, so an ambiguous network failure cannot duplicate a create. Structured `message` and `details` errors, including the current duplicate-record 409 response, remain visible to the user.

## Namecheap

Status: implemented and provider-flow UI test compiled on 2026-07-28. Live
fixture execution requires the credential and code-signing handoff documented
in the README.

Primary evidence:

- [Namecheap API introduction and access requirements](https://www.namecheap.com/support/api/intro/)
- [`namecheap.domains.getList`](https://www.namecheap.com/support/api/methods/domains/get-list/)
- [`namecheap.domains.getTldList`](https://www.namecheap.com/support/api/methods/domains/get-tld-list/)
- [`namecheap.domains.dns.getList`](https://www.namecheap.com/support/api/methods/domains-dns/get-list/)
- [`namecheap.domains.dns.setCustom`](https://www.namecheap.com/support/api/methods/domains-dns/set-custom/)
- [`namecheap.domains.dns.setDefault`](https://www.namecheap.com/support/api/methods/domains-dns/set-default/)
- [`namecheap.domains.dns.getHosts`](https://www.namecheap.com/support/api/methods/domains-dns/get-hosts/)
- [`namecheap.domains.dns.setHosts`](https://www.namecheap.com/support/api/methods/domains-dns/set-hosts/)

Implementation decisions:

- DNSDeck uses Namecheap's production or sandbox API from a fixed allowlist.
  API username, API key, and Namecheap-allowlisted client IPv4 are required and
  stored in the Keychain. Requests use form-encoded POST bodies so API keys do
  not appear in request URLs.
- Domain listing follows the documented 100-item pages. SLD/TLD splitting uses
  the API's TLD list with longest-suffix matching so domains such as
  `example.co.uk` are not split incorrectly. TLD results are cached for the
  provider session.
- Existing Namecheap-registered domains are represented as zones. Registration,
  purchase, cancellation, and hosted-zone create/delete are deliberately not
  exposed. Registrar delegation uses `setCustom`; host records are available
  only while the domain reports that it is using Namecheap DNS.
- Namecheap's `setHosts` operation replaces the complete record set. Before
  every create, edit, or delete, DNSDeck re-reads all hosts, refuses the write
  if the zone contains a native type that cannot be safely round-tripped,
  applies the requested change, sends the complete merged set once, then
  re-reads and compares a canonical multiset up to three times. This protects
  unrelated records and detects propagation or concurrent-change mismatches;
  Namecheap does not expose an ETag or atomic compare-and-swap precondition.
- A, AAAA, ALIAS, CAA, CNAME, NS, and TXT are editable. URL and URL301 are
  preserved during full replacement but remain read-only in DNSDeck. FRAME,
  MX, MXE, and unknown native types block mutations because their complete
  semantics cannot be reconstructed safely from the generic host response.
  In particular, `setHosts` requires an email mode for MX-family records while
  `getHosts` does not return that mode.
- The provider-scoped XCUITest connects the provider, opens an existing fixture
  domain, creates a guard and probe A record, edits and deletes the probe,
  verifies the guard survives each full replacement, removes the guard, and
  points the domain to a disposable external nameserver pair before
  disconnecting. A direct API teardown restores Namecheap default DNS and
  removes only the test-owned host names.

## IONOS

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [IONOS Hosting DNS API reference](https://developer.hosting.ionos.com/docs/dns)
- [Official Hosting DNS OpenAPI 3.0 YAML](https://developer.hosting.ionos.com/assets/kms-swagger-specs/dns.yaml)
- [IONOS Hosting API key portal](https://developer.hosting.ionos.com/keys)
- [IONOS Developer API overview](https://developer.hosting.ionos.com/docs)
- [Current `go-acme/lego` IONOS client](https://github.com/go-acme/lego/tree/main/providers/dns/internal/ionos)
- [`libdns/ionos` full record-management implementation](https://github.com/libdns/ionos)

SDK contract note:

- IONOS does not publish a first-party generated SDK for the Hosting DNS API. Its official [`ionos-cloud/sdk-python-dns`](https://github.com/ionos-cloud/sdk-python-dns) targets the separate Cloud DNS product at `dns.de-fra.ionos.com`, with different authentication and resource contracts, so DNSDeck intentionally does not treat that SDK as evidence for Hosting DNS. The official Hosting OpenAPI schema is the machine-readable source of truth; the mature lego and libdns clients provide independent behavior checks.

Issue evidence:

- [`go-acme/lego` issue #2082 and fix #2083: IONOS returns TXT content quoted](https://github.com/go-acme/lego/issues/2082)
- [`go-acme/lego` issue #2568: authoritative propagation can approach the SOA negative-cache interval](https://github.com/go-acme/lego/issues/2568)
- [`go-acme/lego` issue #1825: an invalid suffix filter surfaced as an API contract failure](https://github.com/go-acme/lego/issues/1825)

Implementation decisions:

- DNSDeck uses the IONOS Hosting DNS origin `https://api.hosting.ionos.com/dns`, authenticated by the complete `prefix.secret` value in `X-API-Key`. It does not send IONOS Cloud bearer tokens or call the Cloud DNS regional API.
- The API lists all zones without pagination. Zone details return the complete record collection, so DNSDeck does not invent cursors or use the error-prone suffix filter. Active apex NS records are surfaced as authoritative nameservers.
- `NATIVE` zones support record changes. `SLAVE` zones remain browsable but are rejected locally as read-only before any mutation request.
- A, AAAA, CAA, CERT, CNAME, DS, HTTPS, LOC, MX, NS, OPENPGPKEY, RP, SMIMEA, SRV, SSHFP, SVCB, TLSA, TXT, and URI follow OpenAPI 1.0.2. SOA is retained in snapshots but is provider-managed and read-only.
- Creates use the documented array-valued batch endpoint. Content, TTL, priority, disabled state, root name, change date, and the complete native response remain preserved per record. MX and SRV priority stay in `prio`; SRV content remains `weight port target`.
- Record `PUT` accepts content, TTL, priority, and disabled state but not name or type. Same-identity edits therefore use `PUT`; rename or type changes create the destination first, remove the source second, and delete the destination as rollback if source removal fails.
- IONOS returns normalized TXT values in quoted DNS character strings. DNSDeck presents those strings unquoted and writes plain content, directly covering issue #2082 without losing escaped quotes or adjacent chunks.
- The official schema recommends a 3,600-second TTL but does not publish a numeric lower bound. DNSDeck conservatively follows the current lego client at 300 seconds. Reads retry bounded transient failures; writes never retry automatically.
- IONOS errors are top-level arrays. DNSDeck retains every machine code and message rather than replacing them with a generic HTTP status.

## Azure DNS

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Azure DNS zones REST API](https://learn.microsoft.com/en-us/rest/api/dns/zones?view=rest-dns-2018-05-01)
- [Azure DNS record sets REST API](https://learn.microsoft.com/en-us/rest/api/dns/record-sets?view=rest-dns-2018-05-01)
- [Create or update a record set](https://learn.microsoft.com/en-us/rest/api/dns/record-sets/create-or-update?view=rest-dns-2018-05-01)
- [Stable Azure DNS 2018-05-01 OpenAPI specification](https://github.com/Azure/azure-rest-api-specs/blob/main/specification/dns/resource-manager/Microsoft.Network/Dns/stable/2018-05-01/dns.json)
- [Official generated Azure SDK for Go DNS client](https://github.com/Azure/azure-sdk-for-go/tree/main/sdk/resourcemanager/dns/armdns)
- [Azure DNS zones and record sets overview](https://learn.microsoft.com/en-us/azure/dns/dns-zones-records)
- [Service-principal authentication](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-service-principal)
- [Create and scope a service principal](https://learn.microsoft.com/en-us/cli/azure/azure-cli-sp-tutorial-1)
- [Azure DNS zone and record protection with RBAC](https://learn.microsoft.com/en-us/azure/dns/dns-protect-zones-recordsets)

Version and client note:

- The latest first-party Go SDK is generated from `2023-07-01-preview`, while Microsoft's current stable REST reference remains `2018-05-01`. DNSDeck uses the stable API for production behavior and cross-checks the shared paths, pagination, models, ETag headers, and long-running zone deletion against the generated SDK. Preview-only DNSSEC record mutations are not exposed through the stable integration.
- Azure does not publish a DNS SDK for Swift. The official OpenAPI document and generated Go SDK are the machine-readable and generated-client evidence; no third-party dependency is added to DNSDeck.

Independent and issue evidence:

- [DNSControl Azure DNS provider](https://github.com/DNSControl/dnscontrol/blob/main/providers/azuredns/azureDnsProvider.go)
- [DNSControl issue #792: subscription accounts with more than 100 zones lost later pages](https://github.com/DNSControl/dnscontrol/issues/792)
- [DNSControl issue #770: record-set `nextLink` pages were not returned](https://github.com/DNSControl/dnscontrol/issues/770)
- [DNSControl issue #2601: Azure HTTP 429 responses needed retry handling](https://github.com/DNSControl/dnscontrol/issues/2601)
- [DNSControl issue #4363: concurrent writes return “Another operation is pending” conflicts](https://github.com/DNSControl/dnscontrol/issues/4363)
- [DNSControl issue #634: A, AAAA, and CNAME aliases use Azure resource IDs](https://github.com/DNSControl/dnscontrol/issues/634)

Implementation decisions:

- DNSDeck obtains ARM tokens from the tenant-specific Microsoft Entra v2 token endpoint using the OAuth client-credentials grant and the `https://management.azure.com/.default` scope. Tenant ID, client ID, client secret, and subscription ID are keychain-backed fields. A default resource group is optional for browsing and required only for zone creation.
- Public zones are discovered subscription-wide across every resource group. The resource group is recovered from each canonical ARM resource ID, avoiding the single-resource-group blind spot in many older clients. Zone and RRset listings follow bounded, cycle-checked, same-origin `nextLink` URLs, directly covering issues #792 and #770.
- Zone details and creation use the stable ARM paths with global location. Creation sends `If-None-Match: *`. Zone deletion sends the last-seen ETag and follows the same-origin `Azure-AsyncOperation` or `Location` URL to a bounded terminal status.
- Azure manages DNS data as RRSets. A, AAAA, CAA, CNAME, MX, NS, PTR, SRV, and TXT values are retained as one multi-value DNSDeck record with one RRset TTL. SOA and unrecognized preview or provider-managed records remain visible but read-only.
- A, AAAA, and CNAME aliases retain `targetResource.id` as provider-specific alias metadata. Literal and alias forms are mutually exclusive on write. TXT character strings are recombined for display and split on UTF-8 boundaries into at most 255-byte segments on write.
- Same-name/type updates use full RRset `PUT` with `If-Match`. Creates and rename destinations use `If-None-Match: *`. Rename/type changes create the destination first, ETag-delete the source second, and attempt an ETag-protected destination rollback if source removal fails.
- Mutation responses retry only explicit 429 throttles and the exact 409 pending-operation conflict, honoring bounded `Retry-After`. Transport failures and permanent 409 conflicts are not retried, avoiding an ambiguous duplicate or overwrite after a lost response.
- ARM and Entra errors preserve nested messages, OAuth descriptions, `x-ms-request-id`, and OAuth correlation IDs. Native zones, record sets, tags, metadata, ETags, aliases, and provisioning fields remain in opaque snapshots.

## Oracle Cloud DNS

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [OCI DNS REST API](https://docs.oracle.com/en-us/iaas/api/#/en/dns/20180115/)
- [OCI request-signing specification](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/signingrequests.htm)
- [OCI API signing-key setup](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm)
- [OCI API requests, pagination, errors, and retry tokens](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/usingapi.htm)
- [Supported public DNS resource-record types](https://docs.oracle.com/en-us/iaas/Content/DNS/Reference/supporteddnsresource.htm)
- [DNS IAM policy reference](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/dnspolicyreference.htm)
- [Official generated OCI Go SDK DNS client](https://github.com/oracle/oci-go-sdk/tree/master/dns)
- [Official generated Go request signer](https://github.com/oracle/oci-go-sdk/blob/master/common/http_signer.go)

Machine-contract note:

- Oracle does not publish the OCI DNS service definition as a raw public OpenAPI artifact. The versioned API Browser and current first-party generated SDK are the available machine contract. DNSDeck fixtures mirror the generated `20180115` paths, request and response models, query parameters, headers, discriminators, pagination, and signing order. No SDK dependency is added to the app.

Independent and issue evidence:

- [DNSControl OCI provider](https://github.com/DNSControl/dnscontrol/blob/main/providers/oracle/oracleProvider.go)
- [DNSControl PR #4316: RRset writes versus batch update performance](https://github.com/DNSControl/dnscontrol/pull/4316)
- [DNSControl issue #3176: only provider-owned apex NS records are protected](https://github.com/DNSControl/dnscontrol/issues/3176)
- [DNSControl issue #3164: trailing-dot normalization differences](https://github.com/DNSControl/dnscontrol/issues/3164)
- [Terraform OCI issue #1750: independently modeled SRV siblings overwrite one another](https://github.com/oracle/terraform-provider-oci/issues/1750)
- [Terraform OCI issue #1411: server-generated record hashes and RRset versions caused drift](https://github.com/oracle/terraform-provider-oci/issues/1411)
- [Terraform OCI issue #2365: aggressive RRset reads triggered HTTP 429 regressions](https://github.com/oracle/terraform-provider-oci/issues/2365)

Implementation decisions:

- DNSDeck signs requests with RSA-SHA256 according to OCI Signature Version 1. GET and DELETE sign date, request-target, and host; POST and PUT additionally sign content length, JSON content type, and the SHA-256 body digest in the exact current SDK order. Unencrypted PKCS#1 and PKCS#8 private keys are supported. Tenancy OCID, user OCID, fingerprint, private key, region, compartment OCID, and optional realm domain are keychain-backed fields.
- The endpoint is realm-aware: standard commercial regions use `dns.{region}.oci.oraclecloud.com`, while government and sovereign users may provide their documented realm domain. Region and realm labels are strictly validated before host construction. Only public `GLOBAL` zones are included; private views and Traffic Management steering policies remain separate OCI surfaces.
- Zone listing follows `opc-next-page` until the header is absent, including valid empty intermediate pages, with cycle and page-count bounds. Creation sends `migrationSource: NONE`, `zoneType: PRIMARY`, and one stable `opc-retry-token` across bounded transient retries, then polls lifecycle state to `ACTIVE`. Delete refreshes details, rejects protected zones, and sends the current ETag in `If-Match`.
- Primary, non-protected public zones are writable. Secondary and protected zones remain browsable but locally read-only. Authoritative nameservers, lifecycle, serial, version, DNSSEC state, tags, scope, type, and protection state remain in native snapshots.
- OCI mutates complete RRSets. A, AAAA, ALIAS, CAA, CERT, CNAME, DHCID, DNAME, DS, IPSECKEY, KEY, KX, LOC, MX, NAPTR, NS, NSAP, PTR, PX, RP, SPF, SRV, SSHFP, TLSA, and TXT follow the public DNS contract. DNSKEY and SOA remain provider-managed and read-only. The native `isProtected` flag, rather than a blanket NS prohibition, controls whether returned NS data can be changed.
- Record collections group every same-domain/type value into one DNSDeck record, preventing the sibling-loss failure in issue #1750. TXT character strings are recombined for display and split into at most 255-byte UTF-8 chunks on write. OCI's trailing-dot presentation is retained; ALIAS targets map to alias metadata.
- Every update and delete first GETs the exact RRset to obtain its current ETag and protection state. Same-identity updates use full-set PUT with `If-Match`. Because OCI has no `If-None-Match` precondition for RRset PUT, creates and rename destinations perform a conflict preflight but retain a documented unavoidable race between that GET and PUT.
- Rename or type changes create the destination before ETag-deleting the source, then attempt ETag-protected rollback if source deletion fails. Write bodies contain only `domain`, `rtype`, `rdata`, and `ttl`; server-generated `recordHash` and `rrsetVersion` are preserved for inspection but never echoed into writes.
- Read requests retry bounded transient responses. Zone creation safely retries transient responses and transport failures because its retry token makes the operation idempotent. RRset PUT and DELETE retry only explicit HTTP 429 responses, never ambiguous transport failures, and operations are sequential rather than fanned out. Structured OCI messages and `opc-request-id` remain visible in errors.

## deSEC

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [deSEC domain-management API](https://desec.readthedocs.io/en/latest/dns/domains.html)
- [deSEC RRset API](https://desec.readthedocs.io/en/latest/dns/rrsets.html)
- [deSEC endpoint reference](https://desec.readthedocs.io/en/latest/endpoint-reference.html)
- [deSEC token and RRset-policy API](https://desec.readthedocs.io/en/latest/auth/tokens.html)
- [deSEC rate-limit reference](https://desec.readthedocs.io/en/latest/rate-limits.html)
- [deSEC API source](https://github.com/desec-io/desecapi)

Machine-contract note:

- deSEC publishes a versioned, field-level REST reference and its API implementation source rather than a standalone OpenAPI artifact. DNSDeck fixtures mirror the documented v1 domain and RRset representations, trailing-slash routes, cursor `Link` headers, and token scheme.

Independent and issue evidence:

- [DNSControl deSEC provider](https://github.com/StackExchange/dnscontrol/tree/master/providers/desec)
- [`libdns/desec` implementation](https://github.com/libdns/desec)
- [`go-acme/lego` issue #1406: authoritative propagation checks can lag after a successful write](https://github.com/go-acme/lego/issues/1406)
- [deSEC community replication incident thread](https://talk.desec.io/t/ns1-desec-io-replication-issues/804)

Implementation decisions:

- DNSDeck authenticates with `Authorization: Token` and one keychain-backed scoped token. Domain create and delete remain available only when the token carries the corresponding explicit permissions; RRset writes respect deSEC's per-domain, subname, and type policies.
- Domain and RRset collections enter cursor mode on the first request and follow only bounded, cycle-checked, same-origin HTTPS links from the response `Link` header. Every endpoint retains deSEC's required trailing slash, including POST routes where redirecting would be unsafe.
- Domain create, details, and delete map directly to the v1 domain lifecycle. The server-provided domain minimum TTL is preserved and applied to every record write; TTLs are capped at the documented 86400-second maximum. DNSDeck surfaces the two authoritative deSEC nameservers.
- Records are modeled as multi-value RRSets. A broad set of current PowerDNS-backed presentation types is editable, while SOA and automatically managed DNSSEC types remain read-only. Provider-managed apex NS is also protected.
- RRset creation uses collection POST. Same-name/type updates use full item PUT, with apex represented as an empty `subname` in JSON and `@` only in item URLs. Rename or type changes create the destination before deleting the source and attempt destination rollback if source deletion fails.
- MX priority and complete multi-value sets are retained. TXT values are quoted for presentation-format writes and recombined for display. Native domains, RRsets, timestamps, and server-normalized record content remain in opaque snapshots.
- Reads use bounded transient retries; writes are not retried after ambiguous failures. DNSDeck does not poll public resolvers after writes because the API's successful publication response and authoritative-network propagation are separate states.

## PowerDNS Authoritative

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [PowerDNS Authoritative HTTP API](https://doc.powerdns.com/authoritative/http-api/)
- [PowerDNS zone and RRset endpoints](https://doc.powerdns.com/authoritative/http-api/zone.html)
- [PowerDNS HTTP route table](https://doc.powerdns.com/authoritative/http-routingtable.html)
- [Official PowerDNS source](https://github.com/PowerDNS/pdns)
- [PowerDNS API test suite](https://github.com/PowerDNS/pdns/tree/master/regression-tests.api)

Machine-contract note:

- PowerDNS publishes an OpenAPI 3.1 description in its documentation build and from each enabled server at `/api/docs`. DNSDeck fixtures mirror the current zone, RRset, record, comment, and error schemas without assuming one deployment's generated server URL.

Independent and issue evidence:

- [DNSControl PowerDNS provider](https://github.com/StackExchange/dnscontrol/tree/master/providers/powerdns)
- [`libdns/powerdns` implementation](https://github.com/libdns/powerdns)
- [PowerDNS discussion #13297: RRset replacement is the native record-removal boundary](https://github.com/PowerDNS/pdns/discussions/13297)
- [PowerDNS discussion #13869: record mutation belongs on Authoritative rather than Recursor](https://github.com/PowerDNS/pdns/discussions/13869)

Implementation decisions:

- DNSDeck accepts a deployment-specific endpoint, API key, optional server ID, and optional default nameserver. Remote endpoints must use HTTPS; plain HTTP is accepted only for loopback development. Userinfo, query strings, and fragments are rejected, and `/api/v1` is appended only when absent.
- The API key is sent only in `X-API-Key`. The server ID defaults to PowerDNS's documented `localhost`. Reads use bounded transient retries while zone and RRset writes are never automatically retried after an ambiguous response.
- Zone list, details, native-zone creation, and deletion map directly to the server-scoped API. Zone details explicitly request RRSets and disabled records. Native and Master zones are writable; Slave and newer secondary-style kinds remain browsable but read-only. Apex NS values are derived from the returned RRsets because the API does not emit the create-only `nameservers` field.
- PowerDNS mutates zones through an RRset-array PATCH. DNSDeck preserves complete multi-value sets, disabled flags, comments, and account attribution. Same-identity edits use `REPLACE`; deletes use `DELETE` without a TTL; rename and type changes submit destination replacement and source deletion in one zone patch.
- Because `REPLACE` overwrites a destination RRset and the API has no create precondition, DNSDeck performs a fresh zone-details conflict check before creates and moves. A deployment can still race between that GET and PATCH; the app does not silently claim stronger concurrency control than PowerDNS exposes.
- TXT presentation strings, MX priority, relative display names, trailing-dot API names, native comments, DNSSEC status, zone kind, and server-native JSON are retained. SOA and DNSSEC-generated types remain read-only through DNSDeck even though advanced PowerDNS operators can manipulate some of them directly.
- Structured PowerDNS errors preserve the primary message and every validation item in the `errors` array. Fixtures also cover endpoint normalization, API-key placement, server IDs, loopback HTTP, disabled records, and transactional change envelopes.

## Scaleway Domains and DNS

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Scaleway Domains and DNS API](https://www.scaleway.com/en/developers/api/domains-and-dns)
- [DNS zone endpoints](https://www.scaleway.com/en/developers/api/domains-and-dns/dns-zones)
- [DNS record endpoints](https://www.scaleway.com/en/developers/api/domains-and-dns/records)
- [Current generated API schemas](https://www.scaleway.com/en/developers/api/domains-and-dns/~schemas)
- [Official generated Go SDK](https://github.com/scaleway/scaleway-sdk-go/tree/master/api/domain/v2beta1)
- [Domains and DNS concepts](https://www.scaleway.com/en/docs/domains-and-dns/reference-content/understanding-domains-and-dns/)

Independent and issue evidence:

- [DNSControl Scaleway provider](https://github.com/StackExchange/dnscontrol/tree/master/providers/scaleway)
- [`libdns/scaleway` implementation](https://github.com/libdns/scaleway)
- [Scaleway Terraform provider DNS resources and issues](https://github.com/scaleway/terraform-provider-scaleway/tree/master/internal/services/domain)

Implementation decisions:

- DNSDeck uses the global Domains and DNS v2beta1 endpoint with `X-Auth-Token`, a keychain-backed secret key, and an explicit Project ID. Registrar operations, access-key identifiers, domain purchases, transfers, contacts, and DNSSEC registrar workflows remain outside this DNS-hosting adapter.
- Zone and record lists traverse numeric pages until `total_count` is satisfied, always scoped to the configured project. Zone deletion sends the API-required `project_id`. Subzone creation chooses the longest currently managed parent domain and sends separate `domain` and `subdomain` fields; an unmatched name is treated as a root zone for a domain already known to Scaleway.
- Active zones using default nameservers are writable. Secondary zones with `ns_master`, and pending, locked, or error zones remain browsable but locally read-only. Scaleway's returned authoritative nameservers and native zone status are surfaced directly.
- Records retain their UUID identity and mutate through the versioned `add`, `set`, and `delete` change envelope. Every write sets `disallow_new_zone_creation: true`, preventing a record typo from implicitly creating a subzone, and asks the API not to echo the entire zone.
- A, AAAA, CAA, CNAME, DNAME, HTTPS, MX, NAPTR, NS, SRV, SVCB, TLSA, and TXT follow the documented current type set. TTL uses the API's unsigned 32-bit range. MX and SRV priority, comments, UUIDs, timestamps, and short record names are retained.
- Geo-IP, HTTP health-check, weighted, and view configurations are preserved as structured native JSON on same-type edits. They are cleared on record-type changes because Scaleway requires exactly one compatible dynamic configuration. DNSDeck surfaces their presence as routing-policy metadata without pretending its generic editor can author those provider-specific policies.
- Scaleway accepts and normalizes non-RFC TXT input, so DNSDeck writes plain TXT content and removes one API-added presentation quote layer for display. Reads retry bounded transient failures; versioned writes are not retried after ambiguous transport outcomes.

## OVHcloud DNS

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [OVHcloud API console and production schema](https://eu.api.ovh.com/console/)
- [Current `domain.json` machine schema](https://eu.api.ovh.com/1.0/domain.json)
- [OVHcloud API credential delegation](https://help.ovhcloud.com/csm/en-api-api-rights-delegation?id=kb_article_view&sysparm_article=KB0068602)
- [Official `go-ovh` client](https://github.com/ovh/go-ovh)
- [Official OVHcloud Terraform DNS record implementation](https://github.com/ovh/terraform-provider-ovh/blob/master/ovh/resource_domain_zone_record.go)

Issue evidence:

- [Terraform provider issue #27: use unauthenticated `/auth/time` instead of requiring `/me`](https://github.com/ovh/terraform-provider-ovh/issues/27)
- [ExternalDNS issue #4948: duplicate records and control-plane publication failures](https://github.com/kubernetes-sigs/external-dns/issues/4948)
- [Official provider zero-ID create workaround](https://github.com/ovh/terraform-provider-ovh/blob/master/ovh/resource_domain_zone_record.go)

Implementation decisions:

- DNSDeck supports the official `ovh-eu`, `ovh-ca`, and `ovh-us` endpoints. Application key, application secret, consumer key, and endpoint selection are keychain-backed. Kimsufi and So You Start are not silently treated as OVHcloud DNS accounts.
- Requests follow OVHcloud's `$1$` SHA-1 signature contract over application secret, consumer key, HTTP method, complete URL, exact JSON body, and server timestamp. DNSDeck obtains time from the unauthenticated `/auth/time` endpoint and caches the local/server delta, avoiding both clock-skew failures and an unnecessary `/me` permission.
- Zone list and details are supported. DNS zone creation is an order/billing workflow, while deletion is an asynchronous service-termination flow requiring out-of-band confirmation; DNSDeck does not misrepresent either as ordinary zone CRUD.
- The production machine schema's A, AAAA, CAA, CNAME, DKIM, DMARC, DNAME, HTTPS, LOC, MX, NAPTR, NS, PTR, RP, SPF, SRV, SSHFP, SVCB, TLSA, and TXT types are exposed. Records retain the server's numeric ID and mutate individually. Type changes create the destination, delete the source, and attempt rollback on failure because OVHcloud's PUT schema does not accept `fieldType`.
- Every successful create, update, delete, or type move is followed by the required zone-refresh POST. Refresh is deliberately not retried after ambiguous failures; a successful record mutation and publication request are separate control-plane operations.
- OVHcloud can return record ID `0` after a successful create. DNSDeck follows the official provider workaround: filter IDs by type and subdomain, inspect newest candidates, and resolve the matching target before returning. Failure to resolve is surfaced explicitly instead of leaving an unaddressable record silently.
- TTL 0 maps to automatic; explicit TTLs are clamped to the documented 60-second minimum. MX priority, apex names, quoted TXT normalization, zone nameservers, DNSSEC support, Anycast state, and native JSON are retained. Reads retry bounded transient failures; signed writes do not.

## IBM NS1 Connect

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Using the IBM NS1 Connect API](https://www.ibm.com/docs/en/ns1-connect?topic=introduction-using-api)
- [Supported DNS record types and answer schemas](https://www.ibm.com/docs/en/ns1-connect?topic=answers-reference-dns-record-types)
- [Secondary-zone behavior](https://www.ibm.com/docs/en/ns1-connect?topic=zones-faqs-secondary)
- [Linked-zone behavior](https://www.ibm.com/docs/en/ns1-connect?topic=zones-creating-linked-zone)
- [Official `ns1-go` v2 SDK](https://github.com/ns1/ns1-go/tree/v2)
- [Official SDK zone client and pagination](https://github.com/ns1/ns1-go/blob/v2/rest/zone.go)
- [Official SDK record client and models](https://github.com/ns1/ns1-go/blob/v2/rest/record.go)

Machine-contract note:

- IBM publishes a browsable API catalog and field-level documentation rather than a stable raw OpenAPI download for the legacy DNS endpoints. DNSDeck fixtures mirror the current first-party SDK's zone, record, answer, Filter Chain, and pagination models and the documented `https://api.nsone.net/v1` routes. No SDK dependency is added to the app.

Independent and issue evidence:

- [DNSControl NS1 provider](https://github.com/DNSControl/dnscontrol/tree/main/providers/ns1)
- [`ns1-go` issue #200: record lists are summaries embedded in zone details](https://github.com/ns1/ns1-go/issues/200)
- [`ns1-go` issue #144: record GET and DELETE require an FQDN](https://github.com/ns1/ns1-go/issues/144)
- [`ns1-go` issue #224: incomplete tag and blocked-tag bodies caused record-write failures](https://github.com/ns1/ns1-go/issues/224)
- [`ns1-go` issue #240: answer feed metadata was missing from older SDK models](https://github.com/ns1/ns1-go/issues/240)
- [DNSControl issue #269: TXT answers must remain one RDATA field](https://github.com/DNSControl/dnscontrol/issues/269)

Implementation decisions:

- DNSDeck uses the legacy DNS base URL with one keychain-backed API key secret in `X-NSONE-Key`. Legacy semantics are retained exactly: PUT creates zones and records, POST updates records, and DELETE removes the complete resource. Reads use bounded transient retries; writes are not retried after ambiguous failures.
- Zone and embedded-record pagination follow `Link` headers with cycle and page-count bounds. Only same-origin HTTPS links are accepted, avoiding the official SDK's compatibility behavior of following or rewriting untrusted pagination URLs. Zone-detail pages are merged by appending their record summaries.
- Complete records are fetched from each summary's FQDN and type because NS1 does not expose a separate record-list operation. This preserves full answer metadata, feeds, regions, filters, tags, client-subnet behavior, ALIAS overrides, and other steering fields instead of treating `short_answers` as the mutation contract.
- Primary zones are writable. Secondary zones must be changed at their primary provider, and linked zones cannot be configured or receive records, so both remain browsable but locally read-only. Linked records and automatically generated DNSSEC, SOA, and NS records are also read-only.
- Records are complete name/type RRSets with one TTL and multiple structured answers. MX, SRV, CAA, TXT, HTTPS, SVCB, and general multi-field RDATA retain their native answer-array shapes. TXT remains one answer field even when it contains spaces. Record paths always use the FQDN, matching issue #144.
- Same-name/type edits POST the complete editable configuration. Rename or type changes PUT the destination first, DELETE the source second, and attempt destination rollback if source removal fails. A record with Filter Chain, region, feed, or answer metadata permits TTL-only changes that preserve the native configuration; generic answer edits are rejected instead of silently deleting traffic-steering state.
- Mutation bodies omit read-only IDs and links. DDI `tags` and `blocked_tags` are emitted only as a pair when either contains state, preventing the partial-field failure documented in issue #224. Server-native zones and records remain available in opaque snapshots.

## UltraDNS

Status: implemented and fixture-verified on 2026-07-10.

Primary evidence:

- [Current UltraDNS REST API User Guide](https://ultra-portalstatic.ultradns.com/static/console/docs/REST-API_User_Guide.pdf)
- [Zone API](https://docs.ultradns.com/Content/REST%20API/Content/REST%20API/Zone%20API/Zone%20API.htm)
- [Zone DTOs](https://docs.ultradns.com/Content/REST%20API/Content/REST%20API/Zone%20API/Zone%20API%20DTOs.htm)
- [Current REST API changes](https://docs.ultradns.com/Content/REST%20API/Content/REST%20API/What%27s%20New.htm)
- [Official UltraDNS Go SDK](https://github.com/ultradns/ultradns-go-sdk)
- [Official Terraform provider](https://github.com/ultradns/terraform-provider-ultradns)

Machine-contract note:

- UltraDNS publishes a versioned field-level REST guide and first-party SDK rather than a standalone OpenAPI artifact for the managed DNS API. DNSDeck fixtures mirror the current 2026 zone, cursor, RRset, result-info, token, profile, and system-generated schemas. No SDK dependency is added to the app.

Independent and issue evidence:

- [Official SDK issue #22: RRset list omitted public offset and limit parameters](https://github.com/ultradns/ultradns-go-sdk/issues/22)
- [Lexicon issue #646: only the first 100 UltraDNS records were returned](https://github.com/AnalogJ/lexicon/issues/646)
- [DNSControl provider request #1533](https://github.com/DNSControl/dnscontrol/issues/1533)

Implementation decisions:

- DNSDeck obtains a short-lived bearer token from `/authorization/token` using the documented form-encoded password grant and keychain-backed API-only username and password. Tokens are cached until shortly before expiry; credentials are never sent to DNS endpoints. Reads retry bounded transient failures while writes do not retry ambiguous outcomes.
- Zone listing uses the `/v3/zones` cursor contract with cycle and page-count bounds. Zone metadata and RRset resources intentionally use the unversioned `/zones/{zone}` paths documented by the current guide and official Go SDK. DNSSEC state, account, status, UltraDNS2 state, registrar nameservers, and native JSON remain available in snapshots. Reverse-zone slashes are percent-encoded as one path segment as required by the zone API.
- Primary active zones are writable. Secondary and alias zones remain browsable but read-only. Zone creation is not exposed because a correct primary create requires account-specific primary-create policy; deletion maps directly to the documented zone endpoint.
- RRset listing uses explicit offset and limit pagination until `totalCount` is satisfied, addressing the exact truncation failures in official SDK issue #22 and Lexicon issue #646. The request includes `systemGeneratedStatus=true` so provider-managed records can be protected locally.
- Standard RRsets use BIND presentation RDATA and one shared TTL. POST creates, PUT replaces the complete owner/type set, and DELETE removes it. DNSDeck deliberately does not use PATCH because the May 2026 contract changed PATCH to append RDATA rather than replace existing values.
- Resource Distribution, SiteBacker, Traffic Controller, Service Failover, and directional profiles remain visible as routing metadata but read-only in the generic editor. Any RRset containing system-generated or UltraDNS2-generated data is also protected, preventing a full-set PUT from deleting provider-owned values.
- Rename or type changes POST the destination before deleting the source and attempt destination rollback if source removal fails. MX priorities, multi-value sets, TXT presentation, APEXALIAS targets, native type numbers, profiles, and generation flags are retained.

## Spaceship

Status: implemented and fixture-verified on 2026-07-13.

Primary evidence:

- [Spaceship Public API documentation and embedded OpenAPI 3.0 contract](https://docs.spaceship.dev/)
- [Spaceship API Manager](https://www.spaceship.com/application/api-manager/)

Machine-contract note:

- Spaceship publishes its OpenAPI 3.0 contract as machine-readable data embedded in the official documentation. DNSDeck fixtures cover the documented domain, DNS record, pagination, mutation, and problem-detail schemas from version 1.0.0. No first-party SDK is currently published or required by the app.

Independent evidence:

- [OpenWrt `ddns-scripts` Spaceship updater](https://gist.github.com/ergolyam/6ea69a7b6c64e7e725b299243a771e1c)

Implementation decisions:

- DNSDeck sends the keychain-backed API key and secret only as `X-API-Key` and `X-API-Secret`. Read-only access requires `domains:read` and `dnsrecords:read`; record mutation additionally requires `dnsrecords:write`.
- Registered domains are presented as zones. The public API exposes domain listing and details but no ordinary DNS-zone create or delete operation, so DNSDeck does not claim zone mutation support.
- Domain and record lists follow bounded `take` and `skip` pagination using the documented maxima of 100 domains and 500 records. Empty pages before the reported total and excessive page counts fail closed instead of returning incomplete state.
- A, AAAA, ALIAS, CAA, CNAME, HTTPS, MX, NS, PTR, SRV, SVCB, TLSA, and TXT records retain their provider-specific structured fields. The documented TTL range is enforced at 60 through 3600 seconds, including the minimum 64-character hexadecimal TLSA association data.
- Only records in the `custom` group are writable. `product` and `personalNs` records remain visible but protected because their lifecycle belongs to Spaceship products or personal-nameserver configuration.
- PUT additions and TTL updates use `force: false` so Spaceship's conflict checker remains active. DELETE uses the complete value-based mutation identity without TTL. Non-TXT values are compared case-insensitively, while TXT values preserve case exactly as required by the API.
- Value, owner, or type changes add the destination before deleting the source and attempt destination rollback if source removal fails. TTL-only changes use one PUT and preserve all native record fields.
- Problem-detail `detail`, field-level validation `data`, and `spaceship-operation-id` are surfaced in provider errors. Reads use bounded transient retries; idempotent value-based PUT and DELETE requests can be retried without creating duplicate records.
