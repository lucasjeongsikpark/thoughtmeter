#!/usr/bin/env bash
# Single source of release configuration for ThoughtMeter.
# Every packaging script sources this file — edit values here only.

# App version for the next release (also injected into Info.plist and the
# extension manifest at package time).
VERSION="0.1.0"

# GitHub coordinates used in the Homebrew cask, About screen, and share card.
REPO_OWNER="jeongsikpark"
REPO_NAME="thoughtmeter"

# macOS bundle identifier.
BUNDLE_ID="org.thoughtmeter.app"

# Chrome Web Store extension ID. Set this after the store assigns one
# (see .local-project/MANUAL_ACTIONS.md item 7); until then release builds
# carry no production ID and Chrome connectivity requires a dev ID.
CHROME_EXTENSION_ID_PROD="UNSET"

# Native messaging host name (must match the extension's connectNative call).
NATIVE_HOST_NAME="org.thoughtmeter.chromehost"
