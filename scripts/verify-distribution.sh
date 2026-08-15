#!/usr/bin/env bash
# Final gate for a PUBLIC release. Strict by design: everything scripts/verify.sh
# tolerates for contributors and CI (ad-hoc signatures, no notarization) is a
# hard failure here.
#
# scripts/verify.sh is deliberately NOT made stricter instead: a contributor
# clone and a CI runner legitimately have no signing certificate, and failing
# them would make `make verify` unusable for everyone but the maintainer (D33).
# Two verifiers, two audiences.
#
# Usage: TM_APPLE_TEAM_ID=<team> scripts/verify-distribution.sh [path-to-app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

: "${TM_APPLE_TEAM_ID:?TM_APPLE_TEAM_ID is required (the Apple Team ID the release must be signed by)}"

APP="${1:-$ROOT/dist/ThoughtMeter.app}"
DMG="$ROOT/dist/ThoughtMeter-$VERSION.dmg"
HOST="$APP/Contents/MacOS/thoughtmeter-native-host"
FAILURES=0

fail() { echo "DIST VERIFY FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

[[ -d "$APP" ]] || { echo "error: app bundle not found at $APP" >&2; exit 1; }
[[ -f "$DMG" ]] || { echo "error: DMG not found at $DMG" >&2; exit 1; }

echo "==> strict signature verification"
codesign --verify --strict --deep --verbose=4 "$APP" 2>/dev/null || fail "app signature does not verify strictly"
codesign --verify --strict --verbose=4 "$HOST" 2>/dev/null || fail "native host signature does not verify strictly"

echo "==> Developer ID, team, and Hardened Runtime"
# Authority= is only emitted at --verbose=2 and above (D31).
for target in "$APP" "$HOST"; do
  name="$(basename "$target")"
  details="$(codesign -dv --verbose=4 "$target" 2>&1)"

  authority="$(printf '%s\n' "$details" | sed -n 's/^Authority=//p' | head -1)"
  case "$authority" in
    "Developer ID Application:"*) ;;
    *) fail "$name is signed by '${authority:-unknown}', expected a Developer ID Application certificate" ;;
  esac

  team="$(printf '%s\n' "$details" | sed -n 's/^TeamIdentifier=//p')"
  [[ "$team" == "$TM_APPLE_TEAM_ID" ]] \
    || fail "$name TeamIdentifier is '${team:-none}', expected '$TM_APPLE_TEAM_ID'"

  # Hardened Runtime shows up as the 'runtime' flag on the code signature.
  flags="$(printf '%s\n' "$details" | sed -n 's/^CodeDirectory .*flags=\([^ ]*\).*/\1/p' | head -1)"
  case "$flags" in
    *runtime*) ;;
    *) fail "$name is not signed with Hardened Runtime (flags=${flags:-none})" ;;
  esac

  # A secure timestamp is required for Developer ID distribution; without it the
  # signature stops validating once the certificate expires.
  printf '%s\n' "$details" | grep -q "^Timestamp=" \
    || fail "$name has no secure timestamp (sign with --timestamp)"

  # Recorded, not asserted: the designated requirement is the string TCC stores
  # when the user grants Input Monitoring. Comparing it across releases is how
  # "the grant survives updates" stays true (D30/D47).
  echo "    $name designated requirement:"
  echo "      $(codesign -d -r- "$target" 2>/dev/null | sed -n 's/^#* *designated => *//p')"
done

echo "==> notarization tickets"
xcrun stapler validate "$APP" >/dev/null 2>&1 || fail "app has no stapled notarization ticket"
xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "DMG has no stapled notarization ticket"

echo "==> Gatekeeper assessment"
# What a downloaded copy is judged by on first launch. Must pass without any
# right-click → Open workaround.
spctl --assess --type execute --verbose=4 "$APP" 2>&1 | sed 's/^/    /' \
  || fail "Gatekeeper rejects the app"

echo "==> bundle, privacy, and network invariants"
"$ROOT/scripts/verify.sh" "$APP" >/dev/null || fail "scripts/verify.sh failed (run it directly for detail)"

if [[ $FAILURES -gt 0 ]]; then
  echo "verify-distribution: $FAILURES failure(s) — DO NOT PUBLISH" >&2
  exit 1
fi
echo "verify-distribution: OK — signed, hardened, timestamped, notarized, stapled, Gatekeeper-clean"
