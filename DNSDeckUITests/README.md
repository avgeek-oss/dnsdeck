# Live provider tests

These signed macOS UI tests connect to real provider accounts and create,
update, import, and delete disposable DNS records. Use a dedicated test zone.
They are not run by ordinary CI or by `make test`.

The ProviderCanaries plan contains Cloudflare, GoDaddy, Amazon Route 53, and
IONOS. A full plan run requires all four fixtures and fails if any are missing.
The individual commands run one provider:

```sh
make test-ui-cloudflare
make test-ui-godaddy
make test-ui-route53
make test-ui-ionos
```

Configure local signing first, then supply `PROVIDER_<NAME>_CREDENTIALS` as a
JSON object and `PROVIDER_<NAME>_ZONE` as the dedicated zone's domain name.
The names are CLOUDFLARE, GODADDY, ROUTE53, and IONOS. Credential fields are
declared in ProviderCanaryDefinition.swift and the app's provider catalogue.
Load actual values with your preferred secret manager; never commit them.

The runner passes fixtures to Xcode through a temporary mode-600 xctestrun
file and removes that file on exit. Keep test-results/ private: screenshots
and logs can contain account and zone data. Tests use DNSDECK_UI_TESTING=1
to isolate application state and clean up test-owned dnsdeck-ui-* records.
If a run is interrupted, inspect and remove its remaining test records.

Before an App Store release, run all four journeys and independently verify
cleanup. Historical evidence in [PROVIDER_VERIFICATION.md](../PROVIDER_VERIFICATION.md)
does not establish that current provider APIs or credentials still work.

[Repository](../README.md)
