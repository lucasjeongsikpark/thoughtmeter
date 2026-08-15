# Security Policy

## Reporting a vulnerability

If the repository's **Security** tab offers "Report a vulnerability", use it —
that opens a private advisory only the maintainers can read.

If you do not see that option, open a normal GitHub issue containing **only**
the words "security issue — requesting private contact", with no technical
detail, and a maintainer will follow up to arrange a private channel. Please
use this route rather than describing the issue publicly.

Please do **not** publicly disclose an unpatched vulnerability before we have
had a reasonable window to coordinate — 90 days, or sooner by agreement.
Good-faith research on your own installation is welcome and appreciated.

## Supported versions

| Version | Supported |
|---|---|
| latest release (0.x) | ✅ fixes go here |
| anything older | ❌ please update |

Pre-1.0, only the newest release receives fixes.

## Sensitive areas

Reports in these areas are especially valuable, because ThoughtMeter's whole
premise is a strict privacy contract:

- **Event handling** — anything that could cause key identities, characters,
  or content to be read, retained, or logged (`EventTapSource`,
  `KeystrokeCounter`, `InputTracker`).
- **Chrome pipeline** — anything that could persist a non-selected hostname,
  a full URL, or page data (`extensions/chrome/`, `NativeHostCore`,
  `thoughtmeter-native-host`).
- **Native messaging manifest / host path handling** — anything that could
  let another process impersonate the host or redirect it.
- **File handling** — data-directory permissions, atomic state files, and
  the uninstall scripts' path validation.
- **Network invariant** — any code path that could cause the app to make a
  network request at all.

## What is out of scope

- Attacks requiring root or another already-compromised process on the
  same machine.
- The fact that the release is not notarized (documented; requires a paid
  Apple Developer membership).
