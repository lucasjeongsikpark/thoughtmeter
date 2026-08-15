#!/usr/bin/env bash
# Package release artifacts: DMG, ZIP, SHA-256 checksums, Homebrew cask,
# Chrome extension zip. Expects scripts/build.sh to have produced dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

APP="$ROOT/dist/ThoughtMeter.app"
[[ -d "$APP" ]] || { echo "error: $APP missing — run scripts/build.sh first" >&2; exit 1; }

# The artifact names and cask come solely from $VERSION — refuse to package
# a stale dist/ app that would claim a version its payload does not contain.
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null || echo "unknown")"
if [[ "$APP_VERSION" != "$VERSION" ]]; then
  echo "error: staged app is $APP_VERSION but release-config VERSION=$VERSION — re-run scripts/build.sh" >&2
  exit 1
fi

# A distribution DMG/ZIP must contain the app that Apple already notarized:
# the ticket is stapled to the .app, so packaging an un-stapled bundle would
# ship artifacts that need a network round-trip (or fail) on first launch.
if [[ "${TM_DISTRIBUTION_BUILD:-0}" == "1" ]] \
   && ! xcrun stapler validate "$APP" >/dev/null 2>&1; then
  echo "error: dist/ThoughtMeter.app has no stapled notarization ticket." >&2
  echo "  Run scripts/notarize-app.sh before packaging a distribution build." >&2
  exit 1
fi

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

echo "==> Chrome extension package (deterministic)"
# The store upload is the one artifact a reader could in principle rebuild and
# compare against what Google serves — but only if packaging is reproducible.
# Plain `zip -r` is not: it records the current mtime, the developer's umask,
# and whatever order the filesystem hands back. Stage, normalize, sort, zip.
rm -f "$EXT_ZIP"
EXT_SRC="$ROOT/extensions/chrome"
# SOURCE_DATE_EPOCH is the cross-project convention for this; default to the
# last commit that touched a file the archive actually CONTAINS. Watching the
# whole directory would restamp the archive for an unrelated README edit.
EXT_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct -- \
  extensions/chrome/manifest.json extensions/chrome/src extensions/chrome/assets 2>/dev/null || true)}"
[[ -n "$EXT_EPOCH" ]] || EXT_EPOCH=1704067200   # 2024-01-01T00:00:00Z
# Zip inherits MS-DOS timestamps: two-second granularity, so an odd epoch
# would round and break byte-equality between runs.
EXT_EPOCH=$(( EXT_EPOCH - EXT_EPOCH % 2 ))

EXT_STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGING" "$EXT_STAGE"' EXIT
(cd "$EXT_SRC" && cp -R manifest.json src assets "$EXT_STAGE/")
find "$EXT_STAGE" -name '.*' -delete
find "$EXT_STAGE" -type d -exec chmod 755 {} +
find "$EXT_STAGE" -type f -exec chmod 644 {} +
# TZ=UTC is load-bearing, not decoration. A zip entry's timestamp is an MS-DOS
# field with NO timezone: `touch` interprets its stamp in local time and `zip`
# writes the mtime back in local time, so the same source in Seoul and in UTC
# would otherwise produce different archive bytes — which is exactly the
# property this block exists to provide. Pinning both to UTC makes the archive
# reproducible across machines, not just across runs on one machine.
(
  export TZ=UTC
  find "$EXT_STAGE" -exec touch -t "$(date -r "$EXT_EPOCH" +%Y%m%d%H%M.%S)" {} +
  # -X drops uid/gid and macOS extended attributes; -@ takes the sorted list so
  # entry order is the sort order rather than directory order.
  cd "$EXT_STAGE" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -X -q "$EXT_ZIP" -@
)

# Checksums and the cask describe FINAL bytes. In a distribution build the DMG
# still has to be signed, notarized, and stapled — all of which rewrite it — so
# hashing is deferred to scripts/finalize-dist.sh after those steps.
if [[ "${TM_DISTRIBUTION_BUILD:-0}" == "1" ]]; then
  echo "==> checksums deferred (distribution build)"
  echo "    next: scripts/notarize-dmg.sh → scripts/verify-distribution.sh → scripts/finalize-dist.sh"
else
  "$ROOT/scripts/finalize-dist.sh"
fi

echo "==> packaged:"
ls -lh "$DMG" "$ZIP" "$EXT_ZIP"
