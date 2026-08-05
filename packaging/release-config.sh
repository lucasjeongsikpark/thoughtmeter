#!/usr/bin/env bash
# Single source of release configuration for ThoughtMeter.
# Every packaging script sources this file — edit values here only.

# macOS app version for the next release, injected into Info.plist at build time.
VERSION="0.1.2"

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
