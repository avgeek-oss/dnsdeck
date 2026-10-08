# Repository guidance

Read README.md, then the README in the area you are changing.

DNSDeck is a native SwiftUI app for iOS and macOS. Keep provider networking in
DNSDeck/Services/Providers and its metadata in DNSDeck/ProviderDefinitions.json.
Preserve all 24 provider implementations and provider-specific mutation guards.
The local packages under packages/ supply localization, networking, and native UI.

Use make build-macos and make build-ios for unsigned Release builds.
Run make test for offline provider and shared package unit tests and make format-check for Swift
formatting. For documentation changes, run npm ci and npm run docs:check.

Live provider tests change real DNS records. Run them only when explicitly
requested, using a dedicated test zone and environment-provided credentials.
Never commit credentials, signing overrides, generated test plans, or build outputs.

Cloudflare is the only live integration test. Do not add live tests for other
providers; use injected transports and local fixtures in Tests/DNSDeckTests.
Before an App Store release, run the signed Cloudflare canary and complete
signing, archive, and device verification. A successful unsigned build is not an
App Store release.
