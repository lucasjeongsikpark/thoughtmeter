#!/usr/bin/env bash
# Check (and where safe, guide installation of) development dependencies.
# ThoughtMeter deliberately needs very little: Swift CLT + node for tests.
set -euo pipefail

MISSING=0

check() {
  local cmd="$1" hint="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ok: $cmd ($(command -v "$cmd"))"
  else
    echo "  MISSING: $cmd — $hint"
    MISSING=$((MISSING + 1))
  fi
}

echo "==> required"
check swift "install Xcode Command Line Tools: xcode-select --install"
check codesign "part of Command Line Tools"
check hdiutil "part of macOS"
check iconutil "part of macOS"
check plutil "part of macOS"

echo "==> required for extension tests"
check node "brew install node (v18+ needed for node --test)"

echo "==> optional"
if command -v xcodegen >/dev/null 2>&1; then
  echo "  ok: xcodegen (Xcode project generation available via 'make generate')"
else
  echo "  not installed: xcodegen — only needed if you want an Xcode project (brew install xcodegen)"
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  echo "WARNING: this machine is $ARCH; ThoughtMeter targets Apple Silicon (arm64) only." >&2
fi

if [[ $MISSING -gt 0 ]]; then
  echo "bootstrap: $MISSING missing dependency(ies)" >&2
  exit 1
fi
echo "bootstrap: OK"
