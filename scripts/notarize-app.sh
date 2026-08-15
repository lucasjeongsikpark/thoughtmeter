#!/usr/bin/env bash
# Submit the Developer-ID-signed ThoughtMeter.app to Apple's notary service and
# staple the resulting ticket to the bundle.
#
# Run AFTER: TM_DISTRIBUTION_BUILD=1 scripts/build.sh release
# Run BEFORE: scripts/package.sh (the DMG and ZIP must contain the stapled app)
#
# Credentials come from a notarytool keychain profile, created once with:
#   xcrun notarytool store-credentials thoughtmeter-notary \
#     --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

APP="$ROOT/dist/ThoughtMeter.app"
PROFILE="${TM_NOTARY_PROFILE:-thoughtmeter-notary}"
UPLOAD="$ROOT/dist/notary-upload-$VERSION.zip"

[[ -d "$APP" ]] || {
  echo "error: $APP missing — run TM_DISTRIBUTION_BUILD=1 scripts/build.sh release first" >&2
  exit 1
}

# Notarization only accepts Developer-ID-signed, hardened code. Catching that
# here gives a readable error instead of an opaque Apple rejection minutes later.
DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if ! grep -q "^Authority=Developer ID Application:" <<<"$DETAILS"; then
  echo "error: $APP is not signed with a Developer ID Application identity." >&2
  echo "  Apple will reject the submission. Re-run the distribution build." >&2
  exit 1
fi
if ! grep -q "flags=.*runtime" <<<"$DETAILS"; then
  echo "error: $APP is not signed with Hardened Runtime (--options runtime)." >&2
  exit 1
fi

echo "==> pre-notarization signature verification"
codesign --verify --strict --deep --verbose=4 "$APP"

echo "==> preparing upload archive"
rm -f "$UPLOAD"
# ditto -c -k --keepParent preserves the bundle's symlinks and extended
# attributes; plain zip(1) mangles a .app and Apple rejects the result.
ditto -c -k --keepParent "$APP" "$UPLOAD"

echo "==> submitting to the Apple notary service (this waits for the verdict)"
if ! xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait; then
  echo "error: notarization failed." >&2
  echo "  Inspect the log with:" >&2
  echo "    xcrun notarytool log <submission-id> --keychain-profile $PROFILE" >&2
  rm -f "$UPLOAD"
  exit 1
fi

echo "==> stapling the ticket to the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

rm -f "$UPLOAD"
echo "notarize-app: OK — $APP is notarized and stapled"
