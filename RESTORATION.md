# SwiftUI restoration

## Source

Restored on 9 October 2026 from monorepo snapshot
`f271be41fbd7e11385e28edab4b483282057e42e`, the first parent of the portable
engine / React Native migration merge `597bbaf4a` (PR #35).

The recovered paths are `apps/dnsdeck-apple`, `packages/apple-foundations`,
and `packages/apple-design-system`. The application and those packages are
identical at `cc4249c24a4e3e0000e38b2532f3958d6f767603`, the parent of the
first shared-engine/mobile implementation commit `322b3d18e`.

This snapshot has native SwiftUI targets for both iOS and macOS and all 24
Swift provider implementations. It includes account management, zone and
record editing, bulk operations, CSV/BIND import, export, Keychain storage,
localization, app locking, and the local macOS MCP companion.

The public repository starts with the recovered product and its required
local packages. Unrelated monorepo history and private infrastructure are
not part of this repository.

## Standalone changes

- Localized Swift package paths and build commands to this repository.
- Added ignored local overrides for signing team and bundle identifier.
- Changed the app accent to deep blue in light mode and a readable lighter
  blue in dark mode, retaining native Apple surfaces and semantic colors.
- Removed the internal AWS Secrets Manager fallback from live test fixtures;
  contributors supply their own credentials through the environment.
- Packaged the MCP provider-data bundle with the application and matched the
  companion's architectures to the macOS app (Apple Silicon and Intel).
- Added an explicit localization import required by the newer Swift compiler.
- Added Apache-2.0 licensing, minimal Mintlify docs, and public CI.

## Verification

Verified locally on 9 October 2026 with Xcode 27.0 (27A266a):

- Release macOS build, with arm64 and x86_64 app and MCP binaries.
- Release iOS Simulator build and unsigned iOS device build.
- macOS UI-test target compilation, without running live provider tests.
- All 22 bundled Swift package tests (14 foundations, 8 design system).
- SwiftFormat validation.
- Mintlify build validation and internal link checks, plus rendered-page review.
- macOS launch, provider settings, and credential form inspection in isolated
  UI-test mode; iOS simulator installation and launch.
- Packaged MCP initialization and provider resource read from outside the
  checkout: all 24 providers loaded successfully.
- Gitleaks scan of the public source with no leaks. Two exact metadata/type
  false positives are documented in .gitleaks.toml.

The older PROVIDER_VERIFICATION.md is retained as historical implementation
evidence, not a claim that provider APIs have been retested for this release.

App Store signing, submission, and current live provider validation are
separate release steps.
