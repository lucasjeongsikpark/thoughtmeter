#!/usr/bin/env bash
# Verify the built app bundle: architecture, structure, signing, privacy.
# Usage: scripts/verify.sh [path-to-ThoughtMeter.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/ThoughtMeter.app}"
FAILURES=0

fail() { echo "VERIFY FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

if [[ ! -d "$APP" ]]; then
  echo "error: app bundle not found at $APP (run make build first)" >&2
  exit 1
fi

echo "==> bundle structure"
for path in \
  "Contents/Info.plist" \
  "Contents/MacOS/ThoughtMeter" \
  "Contents/MacOS/thoughtmeter-native-host" \
  "Contents/Resources/AppIcon.icns" \
  "Contents/PkgInfo"; do
  [[ -e "$APP/$path" ]] || fail "missing $path"
done

echo "==> architecture (arm64 only)"
for binary in ThoughtMeter thoughtmeter-native-host; do
  archs=$(lipo -archs "$APP/Contents/MacOS/$binary" 2>/dev/null || echo "unknown")
  [[ "$archs" == "arm64" ]] || fail "$binary architecture is '$archs', expected arm64"
done

echo "==> Info.plist keys"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || fail "Info.plist does not lint"
for key in CFBundleIdentifier CFBundleShortVersionString LSMinimumSystemVersion LSUIElement; do
  plutil -extract "$key" raw "$APP/Contents/Info.plist" >/dev/null 2>&1 || fail "Info.plist missing $key"
done
min_version=$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")
[[ "$min_version" == "14.0" ]] || fail "LSMinimumSystemVersion is $min_version, expected 14.0"

echo "==> code signature (ad-hoc expected; NOT notarized by design)"
codesign --verify --deep "$APP" || fail "code signature does not verify"
authority=$(codesign -dv "$APP" 2>&1 | grep -E '^Signature' || true)
if codesign -dv "$APP" 2>&1 | grep -q 'Authority=Developer ID'; then
  echo "    note: Developer ID signature found (config says ad-hoc)"
elif codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc'; then
  echo "    ad-hoc signature confirmed"
else
  fail "unexpected signature state: $authority"
fi

echo "==> privacy + network checks"
"$ROOT/scripts/verify-privacy.sh" || FAILURES=$((FAILURES + 1))
"$ROOT/scripts/verify-no-network.sh" "$APP" || FAILURES=$((FAILURES + 1))

if [[ $FAILURES -gt 0 ]]; then
  echo "verify: $FAILURES failure(s)" >&2
  exit 1
fi
echo "verify: OK"
