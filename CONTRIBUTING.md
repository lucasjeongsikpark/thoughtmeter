# Contributing to ThoughtMeter

Thanks for your interest! ThoughtMeter is a small, privacy-first personal
utility, and contributions that keep it small, honest, and boring are the
best kind.

## Development requirements

- macOS 14+ on Apple Silicon
- Xcode **Command Line Tools** (`xcode-select --install`) — full Xcode is *not* required
- Node.js 18+ (extension tests only)

```bash
make bootstrap   # verifies the above
make test        # Swift + extension tests
make dev         # build & launch a debug bundle
make build       # release bundle in dist/
make verify      # bundle + privacy + network verification
```

### Why no Xcode project?

The app builds with Swift Package Manager (`Package.swift`) and
`scripts/build.sh` assembles the `.app` bundle. This keeps the toolchain
requirement to Command Line Tools and makes builds reproducible in CI.
If you prefer Xcode, `make generate` produces a project via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) — it is a
convenience and is not exercised by CI.

### The Input Monitoring dev loop

macOS ties the Input Monitoring grant to the app's code identity. With an
ad-hoc signature that identity is the hash of the compiled code itself, so
**each rebuild silently invalidates the permission** and counting stops until
you toggle ThoughtMeter off and on in System Settings ▸ Privacy & Security ▸
Input Monitoring. The app detects this and shows a warning state, but for a
pleasant dev loop, sign with a stable identity instead:

1. Keychain Access → Certificate Assistant → Create a Certificate…
   Name: `ThoughtMeter Dev`, Identity Type: Self-Signed Root,
   Certificate Type: **Code Signing**.
2. Build with it: `TM_SIGN_IDENTITY="ThoughtMeter Dev" make dev`
3. Grant Input Monitoring once — it now survives rebuilds.

The certificate does not need to be trusted; signing works regardless, and
the resulting designated requirement references the certificate instead of the
code hash. Confirm with `codesign -d -r- <app>`.

Releases use `RELEASE_SIGN_IDENTITY` from `packaging/release-config.sh` for the
same reason, so users grant the permission once rather than after every
update. Builds fall back to ad-hoc when that identity is absent from your
keychain, so cloning and running `make build` works without any setup.

### Why a custom test runner?

Command Line Tools ship neither XCTest nor swift-testing, so tests run
through a tiny zero-dependency harness (`apps/macos/Tests/TestHarness.swift`,
`swift run thoughtmeter-tests`). The assertion API mirrors XCTest naming;
add cases to the relevant `*Tests.swift` file and register new suites in
`apps/macos/Tests/main.swift`.

## Architecture in five lines

- `apps/macos/Sources/ThoughtMeterKit/` — all logic (counting rules, source
  resolution, aggregation, SQLite, Chrome state). No AppKit. Fully tested.
- `apps/macos/Sources/ThoughtMeterApp/` — the menu bar app: event tap,
  monitors, SwiftUI views, coordinator.
- `helpers/chrome-native-host/` — Chrome Native Messaging host (framing +
  decision logic in `NativeHostCore`, tested; thin I/O executable).
- `extensions/chrome/` — MV3 extension; pure logic in `src/lib.js`, tested
  with `node --test`.
- `scripts/` + `Makefile` — build, package, verify. `packaging/release-config.sh`
  is the single source of release configuration.

The hot path contract: the event-tap callback only increments an in-memory
counter. Anything slower (disk, queries, file reads) is a bug.

## Privacy invariants (non-negotiable)

Every change must preserve [PRIVACY.md](PRIVACY.md). In particular:

- Never read or store key identities, characters, or content.
- Never persist full URLs, non-selected hostnames, or window titles.
- Never add network code, telemetry, or third-party analytics.
- Never add an external package dependency without a very strong reason.

`make privacy-check` enforces the mechanical parts and runs in CI; if your
change legitimately needs to touch a guarded pattern, update the check and
PRIVACY.md in the same PR and explain why.

## Adding a recognized application

1. Find the app's real bundle identifier:
   `osascript -e 'id of app "AppName"'` or read its `Info.plist`.
2. Add it to `RecognizedCatalog.apps` in
   `apps/macos/Sources/ThoughtMeterKit/Sources.swift`.
3. Detection verifies against installed bundles at runtime, so a wrong ID
   fails safe — but please verify on a real install and say so in the PR.

## Adding a recognized domain

1. Add it to `RecognizedCatalog.domains` (same file).
2. Domains must pass `DomainNormalizer.normalize`.
3. Add a test case if the domain has interesting subdomain behavior.

## Pull request guidelines

- Run `make test` and `make privacy-check` before opening the PR.
- Keep PRs focused; small and reviewable beats big and clever.
- Match the existing code style (explicit, native APIs, no speculative
  abstraction). New logic belongs in `ThoughtMeterKit` with tests.
- UI changes: include a screenshot (light and dark mode if relevant).
- Behavior changes: update README/PRIVACY/docs in the same PR.

## Release engineering

Maintainers: `make release VERSION=x.y.z` runs tests, builds, packages
(DMG/ZIP/extension zip/checksums), generates the Homebrew cask, and prints
the manual checklist. `packaging/release-config.sh` is the single source for
the app version and IDs; the Chrome extension versions independently through
its own `manifest.json`, which the packaging scripts read for artifact names.
