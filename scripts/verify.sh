#!/usr/bin/env bash
# Verify the built app bundle: architecture, structure, signing, privacy.
# Usage: scripts/verify.sh [path-to-ThoughtMeter.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"
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
  "Contents/Resources/ThoughtMeter_ThoughtMeter.bundle" \
  "Contents/PkgInfo"; do
  [[ -e "$APP/$path" ]] || fail "missing $path"
done

icon_count=$(find "$APP/Contents/Resources/ThoughtMeter_ThoughtMeter.bundle" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
[[ "$icon_count" -ge 20 ]] || fail "bundled domain icons missing (found $icon_count)"

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

echo "==> code signature (NOT notarized by design)"
codesign --verify --deep "$APP" || fail "code signature does not verify"
# Two output quirks worth knowing: Authority= appears only at --verbose=2 and
# above, and the designated requirement (stdout) is prefixed with "# " for
# ad-hoc signatures but not for certificate-backed ones.
details=$(codesign -dv --verbose=2 "$APP" 2>&1)
signature=$(printf '%s\n' "$details" | sed -n 's/^Signature=//p')
authority=$(printf '%s\n' "$details" | sed -n 's/^Authority=//p' | head -1)
requirement=$(codesign -d -r- "$APP" 2>/dev/null | sed -n 's/^#* *designated => *//p')

if [[ -n "${RELEASE_SIGN_IDENTITY:-}" ]]; then
  # A stable identity is configured, so the designated requirement must be
  # anchored to the certificate. If it is pinned to the code hash instead, the
  # build was signed ad-hoc and shipping it would invalidate the Input
  # Monitoring grant of every existing user (DECISIONS D30).
  if [[ "$authority" != "$RELEASE_SIGN_IDENTITY" && "$authority" != "Developer ID"* ]]; then
    fail "signed by '${authority:-${signature:-unknown}}', expected '$RELEASE_SIGN_IDENTITY' (packaging/release-config.sh)"
  fi
  case "$requirement" in
    *"certificate leaf"*|*"anchor apple"*)
      echo "    stable identity confirmed: $authority" ;;
    *)
      fail "designated requirement is pinned to the code hash ($requirement) — every update would break the user's Input Monitoring grant" ;;
  esac
elif [[ "$signature" == "adhoc" ]]; then
  echo "    ad-hoc signature confirmed"
  echo "    note: users must re-grant Input Monitoring after every update"
else
  echo "    signed by: ${authority:-unknown}"
fi

echo "==> privacy + network checks"
"$ROOT/scripts/verify-privacy.sh" || FAILURES=$((FAILURES + 1))
"$ROOT/scripts/verify-no-network.sh" "$APP" || FAILURES=$((FAILURES + 1))

if [[ $FAILURES -gt 0 ]]; then
  echo "verify: $FAILURES failure(s)" >&2
  exit 1
fi
echo "verify: OK"
