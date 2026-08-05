#!/usr/bin/env bash
# Single source of release configuration for ThoughtMeter.
# Every packaging script sources this file — edit values here only.

# App version for the next release (also injected into Info.plist and the
# extension manifest at package time).
VERSION="0.1.0"

# GitHub coordinates used in the Homebrew cask, About screen, and share card.
REPO_OWNER="lucasjeongsikpark"
REPO_NAME="thoughtmeter"

# macOS bundle identifier.
BUNDLE_ID="org.thoughtmeter.app"

# Chrome Web Store extension ID. Set this after the store assigns one
# (see .local-project/MANUAL_ACTIONS.md item 7); until then release builds
# carry no production ID and Chrome connectivity requires a dev ID.
CHROME_EXTENSION_ID_PROD="UNSET"

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
