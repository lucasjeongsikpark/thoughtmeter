#!/usr/bin/env bash
# Package release artifacts: DMG, ZIP, SHA-256 checksums, Homebrew cask,
# Chrome extension zip. Expects scripts/build.sh to have produced dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

APP="$ROOT/dist/ThoughtMeter.app"
[[ -d "$APP" ]] || { echo "error: $APP missing — run scripts/build.sh first" >&2; exit 1; }

DIST="$ROOT/dist"
DMG="$DIST/ThoughtMeter-$VERSION.dmg"
ZIP="$DIST/ThoughtMeter-$VERSION.zip"
EXT_ZIP="$DIST/thoughtmeter-extension-$EXT_VERSION.zip"

echo "==> DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/ThoughtMeter.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "ThoughtMeter" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"

echo "==> ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Chrome extension package"
rm -f "$EXT_ZIP"
(cd "$ROOT/extensions/chrome" && zip -q -r "$EXT_ZIP" manifest.json src assets)

echo "==> checksums"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" "$(basename "$EXT_ZIP")" > SHA256SUMS.txt)
cat "$DIST/SHA256SUMS.txt"

echo "==> Homebrew cask"
DMG_SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
sed -e "s/__VERSION__/$VERSION/g" \
    -e "s/__SHA256__/$DMG_SHA/g" \
    -e "s/__OWNER__/$REPO_OWNER/g" \
    -e "s/__REPO__/$REPO_NAME/g" \
    "$ROOT/packaging/homebrew/thoughtmeter.rb.tmpl" > "$DIST/thoughtmeter.rb"
echo "    wrote dist/thoughtmeter.rb"

echo "==> packaged:"
ls -lh "$DMG" "$ZIP" "$EXT_ZIP"
