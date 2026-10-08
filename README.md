# DNSDeck

A native SwiftUI DNS client for iPhone, iPad, and Mac. Manage accounts, zones,
and records across 24 DNS providers from one app, with credentials stored in
Apple Keychain.

DNSDeck is being prepared for its return to the App Store as a paid app.
You can also clone this repository and build it for yourself.

## Build

Use a Mac with Xcode 26 or newer and its iOS platform support installed.
The deployment targets are iOS 18.0 and macOS 15.6.

```sh
git clone https://github.com/avgeek-oss/DNSDeck.git
cd DNSDeck
make build-macos
make build-ios
```

These commands produce unsigned Release builds without an Apple developer
account. The macOS build includes the local DNSDeckMCP companion.
All Swift dependencies are included in this repository; no Node.js, Rust,
server, or private package registry is needed to build the app.

For a signed build on your Mac or iPhone, copy
`Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`,
enter your team ID and a unique bundle identifier, then open
`DNSDeck.xcodeproj`. Choose **DNSDeck macOS** or **DNSDeck iOS** and run it.
The local signing file is ignored by Git.

Read the [build guide](docs/build-from-source.mdx) for signing and output paths.

## Providers

Cloudflare, DigitalOcean, Hetzner, Akamai Cloud, Vultr, DNSimple, Gandi LiveDNS,
GoDaddy, Porkbun, Name.com, Namecheap, Spaceship, IONOS, Azure DNS, Oracle Cloud
DNS, deSEC, PowerDNS Authoritative, Scaleway, OVHcloud DNS, IBM NS1 Connect,
UltraDNS, Amazon Route 53, Vercel, and Google Cloud DNS.

Features depend on each provider's API. The app exposes supported record types,
zone operations, TTL rules, and credential requirements from its
[provider catalogue](DNSDeck/ProviderDefinitions.json).

## Documentation

Minimal Mintlify documentation lives in [docs/](docs/README.md): getting
started, building your own copy, provider setup, and security.

Node.js is needed only to work on the documentation:

```sh
npm ci
npm run docs:dev
npm run docs:check
```

The local documentation preview uses port 4187.

## Development

```sh
make test             # Shared Swift package tests; no provider credentials
make build-ui-tests   # Compile the macOS provider test target without running it
make format-check     # Requires SwiftFormat
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[live provider test guide](DNSDeckUITests/README.md).

This repository restores the final pre-React-Native SwiftUI implementation.
[RESTORATION.md](RESTORATION.md) records the source snapshot and verification.

Licensed under [Apache-2.0](LICENSE). Provider names and artwork belong to
their respective owners; see [NOTICE](NOTICE).
