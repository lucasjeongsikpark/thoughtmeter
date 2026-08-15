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

# Distribution preconditions are checked BEFORE anything is built: a late
# failure would leave an assembled but unsigned dist/ThoughtMeter.app behind,
# which scripts/package.sh would happily package.
DISTRIBUTION="${TM_DISTRIBUTION_BUILD:-0}"
if [[ "$DISTRIBUTION" == "1" ]]; then
  if [[ "$CONFIG" != "release" ]]; then
    echo "error: TM_DISTRIBUTION_BUILD=1 requires the release configuration, got '$CONFIG'" >&2
    exit 1
  fi
  : "${TM_SIGN_IDENTITY:?TM_SIGN_IDENTITY is required for a distribution build (Developer ID Application identity)}"
  : "${TM_APPLE_TEAM_ID:?TM_APPLE_TEAM_ID is required for a distribution build}"

  if [[ "$TM_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
    echo "error: a distribution build requires a 'Developer ID Application: …' identity" >&2
    echo "  got: $TM_SIGN_IDENTITY" >&2
    echo "  list yours with: security find-identity -v -p codesigning" >&2
    exit 1
  fi
  if ! security find-identity -p codesigning 2>/dev/null | grep -q "$TM_SIGN_IDENTITY"; then
    echo "error: distribution identity '$TM_SIGN_IDENTITY' is not in the keychain." >&2
    echo "  Refusing to fall back to ad-hoc signing for a distribution build." >&2
    exit 1
  fi
fi

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

# SPM resource bundle (bundled domain icons) → Contents/Resources. The app
# resolves it via Bundle.main.resourceURL (IconCache) — Bundle.module must
# never be used: its accessor checks only the .app ROOT and the build
# machine's absolute .build path, so it crashes on every other machine
# (verify.sh's clean-machine launch guard exists for exactly this).
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

HOST_BINARY="$APP/Contents/MacOS/thoughtmeter-native-host"

# Two signing modes, deliberately kept apart.
#
# DEFAULT (contributors, CI, dev loop): TM_SIGN_IDENTITY env →
# RELEASE_SIGN_IDENTITY from release-config.sh → ad-hoc. A stable certificate
# keeps the code identity constant so the Input Monitoring grant survives
# rebuilds and user updates; ad-hoc pins it to the code hash, which every build
# changes (D30). Falling back to ad-hoc is correct here: a contributor without
# the certificate must still be able to clone and build (D33).
#
# DISTRIBUTION (TM_DISTRIBUTION_BUILD=1): Developer ID Application identity,
# Hardened Runtime, and a secure timestamp — what Apple requires to notarize
# software distributed outside the App Store. This mode FAILS CLOSED: there is
# no fallback, because an ad-hoc or self-signed public release would break
# every existing user's Input Monitoring grant and Gatekeeper besides (D47).
# (Distribution preconditions were validated at the top of this script.)

if [[ "$DISTRIBUTION" == "1" ]]; then
  # Inside-out: nested code first, then the bundle that contains it. --deep is
  # deliberately not used to CREATE these signatures (it is a verification
  # convenience, and signing nested code explicitly is auditable).
  # --timestamp contacts Apple's timestamp server: this is build-time tooling,
  # unrelated to the app's own no-network invariant.
  # No --entitlements on purpose: a listen-only CGEventTap is governed by TCC,
  # not by a Hardened Runtime exception. Do not add permissive entitlements
  # (disable-library-validation, allow-unsigned-executable-memory, …) unless a
  # specific, demonstrated runtime failure requires one.
  echo "==> distribution signing: native host (Hardened Runtime + timestamp)"
  codesign --force --options runtime --timestamp --sign "$TM_SIGN_IDENTITY" "$HOST_BINARY"

  echo "==> distribution signing: app bundle (Hardened Runtime + timestamp)"
  codesign --force --options runtime --timestamp --sign "$TM_SIGN_IDENTITY" "$APP"

  codesign --verify --strict --deep --verbose=4 "$APP"

  # Authoritative team check: the identity string may or may not spell the team
  # out, but the signature always carries it.
  for target in "$APP" "$HOST_BINARY"; do
    team="$(codesign -dv --verbose=4 "$target" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    if [[ "$team" != "$TM_APPLE_TEAM_ID" ]]; then
      echo "error: $(basename "$target") is signed by team '$team', expected '$TM_APPLE_TEAM_ID'" >&2
      exit 1
    fi
  done
  echo "==> distribution signature OK (team $TM_APPLE_TEAM_ID, Hardened Runtime, timestamped)"
  echo "    next: scripts/notarize-app.sh (the app is signed but NOT yet notarized)"
else
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
fi

echo "==> built $APP ($CONFIG, $VERSION)"
