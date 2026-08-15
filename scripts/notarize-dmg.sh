#!/usr/bin/env bash
# Sign, notarize, and staple the release DMG.
#
# The DMG needs its own notarization pass even though it contains an already
# notarized app: Gatekeeper checks the disk image the user actually downloads,
# and a stapled DMG works offline on first mount.
#
# Run AFTER: scripts/package.sh
# Run BEFORE: scripts/finalize-dist.sh (stapling changes the DMG's bytes, so
# checksums and the Homebrew cask must be generated after this script).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

: "${TM_SIGN_IDENTITY:?TM_SIGN_IDENTITY is required (Developer ID Application identity)}"

DMG="$ROOT/dist/ThoughtMeter-$VERSION.dmg"
PROFILE="${TM_NOTARY_PROFILE:-thoughtmeter-notary}"

[[ -f "$DMG" ]] || {
  echo "error: $DMG missing — run scripts/package.sh first" >&2
  exit 1
}

if [[ "$TM_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "error: expected a 'Developer ID Application: …' identity, got: $TM_SIGN_IDENTITY" >&2
  exit 1
fi

echo "==> signing the DMG"
# No --options runtime here: Hardened Runtime is a property of executable code,
# not of a disk image. The secure timestamp still applies.
codesign --force --timestamp --sign "$TM_SIGN_IDENTITY" "$DMG"
codesign --verify --verbose=4 "$DMG"

echo "==> submitting the DMG to the Apple notary service"
if ! xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait; then
  echo "error: DMG notarization failed." >&2
  echo "  Inspect the log with:" >&2
  echo "    xcrun notarytool log <submission-id> --keychain-profile $PROFILE" >&2
  exit 1
fi

echo "==> stapling the ticket to the DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "notarize-dmg: OK — $(basename "$DMG") is notarized and stapled"
echo "    next: scripts/verify-distribution.sh, then scripts/finalize-dist.sh"
