#!/usr/bin/env bash
# Build ThoughtMeter and assemble the .app bundle. No Xcode required.
# Usage: scripts/build.sh [debug|release]   (default: release)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

case "$CONFIG" in
  release) OUT_DIR="$ROOT/dist" ;;
  debug)   OUT_DIR="$ROOT/.build/dev" ;;
  *) echo "error: unknown configuration '$CONFIG' (use debug or release)" >&2; exit 1 ;;
esac

echo "==> swift build ($CONFIG, arm64)"
swift build --package-path "$ROOT" -c "$CONFIG" --arch arm64

BIN_DIR="$ROOT/.build/arm64-apple-macosx/$CONFIG"
for binary in ThoughtMeter thoughtmeter-native-host; do
  if [[ ! -x "$BIN_DIR/$binary" ]]; then
    echo "error: expected binary missing: $BIN_DIR/$binary" >&2
    exit 1
  fi
done

APP="$OUT_DIR/ThoughtMeter.app"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/ThoughtMeter" "$APP/Contents/MacOS/ThoughtMeter"
cp "$BIN_DIR/thoughtmeter-native-host" "$APP/Contents/MacOS/thoughtmeter-native-host"

# SPM resource bundle (bundled domain icons). Bundle.module finds it in
# Contents/Resources of the assembled app.
if [[ -d "$BIN_DIR/ThoughtMeter_ThoughtMeter.bundle" ]]; then
  cp -R "$BIN_DIR/ThoughtMeter_ThoughtMeter.bundle" "$APP/Contents/Resources/"
else
  echo "error: SPM resource bundle missing (expected $BIN_DIR/ThoughtMeter_ThoughtMeter.bundle)" >&2
  exit 1
fi

if [[ ! -f "$ROOT/apps/macos/Resources/AppIcon.icns" ]]; then
  echo "==> generating app icon"
  (cd "$ROOT" && swift scripts/gen-icons.swift >/dev/null)
  iconutil -c icns "$ROOT/apps/macos/Resources/AppIcon.iconset" -o "$ROOT/apps/macos/Resources/AppIcon.icns"
fi
cp "$ROOT/apps/macos/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

sed -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
    -e "s/__EXTENSION_ID__/$CHROME_EXTENSION_ID_PROD/g" \
    -e "s/__REPO_OWNER__/$REPO_OWNER/g" \
    -e "s/__REPO_NAME__/$REPO_NAME/g" \
    "$ROOT/apps/macos/Resources/Info.plist.tmpl" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Code signing (never notarization — there is no Apple Developer Program here).
# Preference order: TM_SIGN_IDENTITY env → RELEASE_SIGN_IDENTITY from
# release-config.sh → ad-hoc. A stable certificate keeps the code identity
# constant so the Input Monitoring grant survives rebuilds and user updates;
# ad-hoc pins it to the code hash, which every build changes (DECISIONS D30).
SIGN_IDENTITY="${TM_SIGN_IDENTITY:-${RELEASE_SIGN_IDENTITY:--}}"

# -p codesigning without -v on purpose: a self-signed certificate is untrusted
# (CSSMERR_TP_NOT_TRUSTED) yet signs perfectly well, and -v would hide it.
if [[ "$SIGN_IDENTITY" != "-" ]] \
  && ! security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  echo "==> note: signing identity '$SIGN_IDENTITY' is not in the keychain — falling back to ad-hoc"
  SIGN_IDENTITY="-"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "==> ad-hoc code signing (rebuilds reset the Input Monitoring grant)"
else
  echo "==> code signing with identity: $SIGN_IDENTITY"
fi
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep "$APP"

echo "==> built $APP ($CONFIG, $VERSION)"
