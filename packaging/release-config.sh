#!/usr/bin/env bash
# Single source of release configuration for ThoughtMeter.
# Every packaging script sources this file — edit values here only.

# macOS app version for the next release, injected into Info.plist at build time.
VERSION="0.2.1"

# The Chrome extension carries its own version in its manifest: it ships to the
# Web Store on its own cadence and is NOT tied to VERSION above. Read it here so
# artifact names can never claim a version the package does not contain.
# Every script defines ROOT before sourcing this file; the BASH_SOURCE fallback
# only matters if that ever stops being true (and is empty under zsh, so it is
# deliberately not the primary path).
_tm_root="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
EXT_VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$_tm_root/extensions/chrome/manifest.json" | head -1)"
unset _tm_root

# GitHub coordinates used in the Homebrew cask, About screen, and share card.
REPO_OWNER="lucasjeongsikpark"
REPO_NAME="thoughtmeter"

# macOS bundle identifier.
BUNDLE_ID="org.thoughtmeter.app"

# Chrome Web Store extension ID, assigned when the store item was created.
# Baked into Info.plist as TMChromeExtensionID, which the app uses to write the
# native-host manifest's allowed_origins. A locally saved dev ID (Settings ▸
# Chrome) is appended alongside it, so an unpacked extension keeps working.
CHROME_EXTENSION_ID_PROD="omhnbpfiapchifodmobgeglhgpgolmhn"

# Chrome rejects a native-messaging manifest wholesale when ONE allowed_origins
# entry is malformed, so a typo here would sever the store extension's
# connection for every user of the release — and present only as "Not
# connected", with nothing pointing back at this file. The same 32-letters-a–p
# rule already gates the development ID in three places; validate the release ID
# on the same terms rather than trusting it because it is checked in.
if [[ "$CHROME_EXTENSION_ID_PROD" != "UNSET" \
   && ! "$CHROME_EXTENSION_ID_PROD" =~ ^[a-p]{32}$ ]]; then
  echo "error: CHROME_EXTENSION_ID_PROD is not a valid Chrome extension ID" >&2
  echo "  value: '$CHROME_EXTENSION_ID_PROD'" >&2
  echo "  expected: exactly 32 letters a-p, or the literal UNSET" >&2
  echo "  fix it in packaging/release-config.sh — nothing was built or packaged." >&2
  # This file is sourced: return unwinds the caller's `source`, and the callers
  # all run under `set -e`. exit covers the (unsupported) direct-execution case.
  return 1 2>/dev/null || exit 1
fi

# Native messaging host name (must match the extension's connectNative call).
NATIVE_HOST_NAME="org.thoughtmeter.chromehost"

# Code-signing identity for builds. Any stable code-signing certificate (a
# self-signed one is enough) keeps the app's code identity constant across
# versions, so macOS does NOT invalidate the user's Input Monitoring grant when
# they update. Ad-hoc signing pins the grant to the code hash instead, which
# every new build changes — verified empirically, see DECISIONS.md D30.
#
# This is NOT notarization: Gatekeeper still blocks the first launch, and no
# release material may claim otherwise.
#
# Builds fall back to ad-hoc when this identity is absent from the keychain, so
# contributors can build without one. Releases refuse to (scripts/release.sh).
RELEASE_SIGN_IDENTITY="ThoughtMeter"
