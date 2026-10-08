# Offline unit tests

Run from the repository root on a Mac with Xcode selected:

```sh
make test-providers  # Provider/core tests and coverage
make test           # Also tests both bundled Swift packages
swift test --filter NamecheapProviderTests
swift test --show-codecov-path
```

DNSDeckTests imports the production Swift provider code compiled by the
DNSDeckMCP SwiftPM target. This is the same source used by the SwiftUI app.
Tests inject recording transports and synthetic HTTP/XML/JSON responses.
They never need an account, API key, domain, server, or simulator.
Delays are injected and RSA keys are generated in memory for signing tests.

Cloudflare's separate [live UI journey](../DNSDeckUITests/README.md) is the
only integration test. Neither unit-test command invokes it.

## Coverage

Each provider has a dedicated *ProviderTests.swift suite. Common suites cover
request conversion, nameserver changes, provider registration, metadata, TTL,
validation, model coding, and error handling.

| Provider | Representative unit checks |
| --- | --- |
| Cloudflare | Authenticated pagination, account-scoped creation, CRUD, structured records, HTTP and failure envelopes |
| DigitalOcean | Trusted pagination, rate limits, domain/record CRUD, SRV/CAA, errors |
| Hetzner | Action polling, three-read consistency, RRset rename/delete, TTL, provider failures |
| Akamai Cloud | Pagination, CRUD, discrete TTL, SRV/CAA, secondary-zone guards |
| Vultr | Cursor pagination, CRUD, MX/SRV priority, partial updates, type-change guards |
| DNSimple | Account scope, pagination, CRUD, native fields, aliases, errors |
| Gandi | PAT authentication, record-set replacement, TXT chunking, rename, SOA guard |
| GoDaddy | Bearer token, pagination, record-set replacement, SRV siblings, rollback |
| Porkbun | Authentication, pagination, idempotent create, record edits, API-status errors |
| Name.com | Basic auth, bounded pagination, CRUD, multi-value creation, rate-limit errors |
| Namecheap | XML auth, multi-label TLDs, full-zone replacement, sibling preservation, duplicate verification, unsafe-type guards |
| Spaceship | Header auth, pagination, record changes, native data, unsupported operations |
| IONOS | Hosting API key, batched CRUD, TXT normalization, rename rollback, slave-zone guard |
| Azure DNS | OAuth token caching, trusted/cyclic pagination, conditional writes, rollback, polling |
| Oracle Cloud | RSA request signing, realm validation, ETags, stable retry token, rollback, protected records |
| deSEC | Trusted pagination, RRsets, TXT chunking, provider errors, SOA guards |
| PowerDNS | Endpoint validation, loopback exception, RRset patch, disabled values, secondary-zone guard |
| Scaleway | Project scope, pagination, versioned changes, advanced configuration, unsupported zone creation |
| OVHcloud | Server time, request signing, native IDs, CRUD/refresh, endpoint validation |
| IBM NS1 | API key, pagination, full record loading, advanced configuration, read-only zones |
| UltraDNS | Token caching, pagination, RRsets, pools, automatic records |
| Route 53 | SigV4, zone/record cursors, XML CRUD, atomic replacement, routing metadata, mixed MX priorities |
| Vercel | Team scope, cursors, versioned CRUD, MX priority, error bodies |
| Google Cloud | Verifiable RSA JWT, token caching, malformed-key rejection, pagination, exact RRset changes |

ProviderHTTPClientTests separately covers origin checks before credentials
are resolved, cyclic/unbounded pagination, bounded retries, Retry-After
clamping, cancellation, and ambiguous write failures.

This is not exhaustive branch coverage and is not proof of live API
compatibility. OAuth expiry/concurrency, presentation-cache behavior, actual
provider propagation, and SwiftUI layout still need focused follow-up.
Coverage reports measure executed code, not API correctness.

## Adding tests

- Inject a transport in every service test. Do not use URLSession or read
  credentials from Keychain or the environment.
- Assert the method, endpoint, scope, and body as well as the decoded result.
- Include errors and preservation of fields the user did not edit.
- Use finite fixtures and a no-op/recording sleep. Never wait for real DNS.
- Add the suite to ProviderCatalogueTests when adding a provider.
- Keep whole-zone and RRset safety checks provider-specific. For example,
  Namecheap intentionally blocks full replacement when unsupported native
  records, including MX/MXE, cannot be safely preserved.
