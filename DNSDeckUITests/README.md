# Cloudflare live integration test

Cloudflare is the only live integration test. Its single signed macOS UI
journey connects to an account and creates, updates, imports, and deletes
disposable DNS records. It is not run by CI or by `make test`.

All 24 providers have credential-free [unit tests](../Tests/README.md).

## Run

Configure local signing and choose a dedicated Cloudflare test zone. Then
supply these environment variables from your preferred secret manager:

- `PROVIDER_CLOUDFLARE_CREDENTIALS`: a JSON object with `accountId` and `token`.
- `PROVIDER_CLOUDFLARE_ZONE`: the dedicated zone's domain name.

Never put real values in source files or shell history.

```sh
make test-ui-cloudflare
```

`make build-ui-tests` only compiles this test target. It does not run the test,
require provider credentials, or connect to Cloudflare.

## Isolation and cleanup

The runner passes fixtures to Xcode through a temporary mode-600 xctestrun
file and removes it on exit. Keep test-results/ private. Screenshots and logs
can contain account and zone data.

The app runs with DNSDECK_UI_TESTING=1 to isolate local state. The journey uses
dnsdeck-ui-* record names and cleans up run-owned records. Its stale-record
cleanup can also remove old canary records in the dedicated test zone. If a
run is interrupted, inspect and remove its remaining test records.

Before an App Store release, run this journey and independently verify cleanup.

[Repository](../README.md)
