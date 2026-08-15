#!/usr/bin/env bash
# Generate SHA256SUMS.txt and the Homebrew cask from the FINAL release
# artifacts — the last step that touches dist/.
#
# This is a separate script because ordering is a correctness property, not a
# style choice: signing and stapling rewrite the DMG's bytes, so a checksum
# taken before either one describes a file that will never be published. In a
# distribution build this script refuses to run until the DMG carries a stapled
# notarization ticket.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

DIST="$ROOT/dist"
DMG="$DIST/ThoughtMeter-$VERSION.dmg"
ZIP="$DIST/ThoughtMeter-$VERSION.zip"
EXT_ZIP="$DIST/thoughtmeter-extension-$EXT_VERSION.zip"

for artifact in "$DMG" "$ZIP" "$EXT_ZIP"; do
  [[ -f "$artifact" ]] || {
    echo "error: $(basename "$artifact") missing — run scripts/package.sh first" >&2
    exit 1
  }
done

if [[ "${TM_DISTRIBUTION_BUILD:-0}" == "1" ]]; then
  echo "==> confirming the artifacts are notarized before hashing them"
  if ! xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    echo "error: $(basename "$DMG") has no stapled notarization ticket." >&2
    echo "  Run scripts/notarize-dmg.sh first — hashing now would publish a" >&2
    echo "  checksum for bytes that stapling is about to change." >&2
    exit 1
  fi
  if ! xcrun stapler validate "$DIST/ThoughtMeter.app" >/dev/null 2>&1; then
    echo "error: dist/ThoughtMeter.app has no stapled notarization ticket." >&2
    echo "  Run scripts/notarize-app.sh, then re-package and re-notarize the DMG." >&2
    exit 1
  fi
fi

echo "==> checksums"
(cd "$DIST" && shasum -a 256 \
  "$(basename "$DMG")" "$(basename "$ZIP")" "$(basename "$EXT_ZIP")" > SHA256SUMS.txt)
cat "$DIST/SHA256SUMS.txt"

echo "==> Homebrew cask"
DMG_SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
sed -e "s/__VERSION__/$VERSION/g" \
    -e "s/__SHA256__/$DMG_SHA/g" \
    -e "s/__OWNER__/$REPO_OWNER/g" \
    -e "s/__REPO__/$REPO_NAME/g" \
    "$ROOT/packaging/homebrew/thoughtmeter.rb.tmpl" > "$DIST/thoughtmeter.rb"
echo "    wrote dist/thoughtmeter.rb (DMG sha256 $DMG_SHA)"

echo "finalize-dist: OK"
echo "    Do NOT rebuild or re-package after this point — hdiutil output is not"
echo "    byte-reproducible, so the published hash would drift (D35)."
