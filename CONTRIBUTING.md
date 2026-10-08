# Contributing

Open DNSDeck.xcodeproj with Xcode 26 or newer. The iOS and macOS targets share
SwiftUI screens and Swift provider clients. Local Swift packages under
packages/ provide common UI, localization, and networking.

For a code change, run the relevant build and package tests:

```sh
make build-macos
make build-ios
make test
make format-check
```

Install SwiftFormat with `brew install swiftformat` if needed. Use
`make format` to apply the repository's formatting rules. Documentation has
its own checks: `npm ci && npm run docs:check`.

Provider changes must keep the catalogue, service factory, provider models,
and credential handling consistent. Preserve provider-native fields when
editing records and reject mutations that cannot safely round-trip data.

Live DNS tests require explicit setup and a disposable zone. See
[DNSDeckUITests/README.md](DNSDeckUITests/README.md). Do not put credentials,
signing files, screenshots of private accounts, or generated test results in
pull requests.
