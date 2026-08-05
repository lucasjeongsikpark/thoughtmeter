#!/usr/bin/env bash
# Verify built binaries reference no networking APIs.
# Usage: scripts/verify-no-network.sh [path-to-ThoughtMeter.app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/dist/ThoughtMeter.app}"

if [[ ! -d "$APP" ]]; then
  echo "error: app bundle not found at $APP (run make build first)" >&2
  exit 1
fi

FAILURES=0
for binary in "$APP/Contents/MacOS/ThoughtMeter" "$APP/Contents/MacOS/thoughtmeter-native-host"; do
  name="$(basename "$binary")"
  echo "==> $name"

  # Fail CLOSED: a missing or unreadable binary must fail the scan. Piping a
  # failed otool/nm/strings into grep hands grep empty input, which satisfies
  # every negative check vacuously and prints OK for a binary never scanned.
  if [[ ! -f "$binary" ]]; then
    echo "NETWORK FAIL: binary missing: $binary" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if ! LINKED="$(otool -L "$binary" 2>/dev/null)"; then
    echo "NETWORK FAIL: otool cannot read $binary (not a valid Mach-O?)" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if ! SYMBOLS="$(nm -u "$binary" 2>/dev/null)"; then
    echo "NETWORK FAIL: nm cannot read $binary" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  if ! CLASS_STRINGS="$(strings - "$binary" 2>/dev/null)"; then
    echo "NETWORK FAIL: strings cannot read $binary" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi

  # 1. Linked libraries: no networking frameworks.
  if grep -iE 'CFNetwork|Network\.framework|libcurl' <<<"$LINKED" >&2; then
    echo "NETWORK FAIL: $name links a networking framework" >&2
    FAILURES=$((FAILURES + 1))
  fi

  # 2. Undefined symbols: no URL-loading / socket client references.
  if grep -iE 'URLSession|NSURLConnection|nw_connection|CFHTTP|CFSocketCreate|getaddrinfo|curl_' <<<"$SYMBOLS" >&2; then
    echo "NETWORK FAIL: $name references networking symbols" >&2
    FAILURES=$((FAILURES + 1))
  fi

  # 3. Objective-C class references (covers dynamic URLSession use).
  if grep -xE 'NSURLSession(Configuration)?|NSURLRequest' <<<"$CLASS_STRINGS" >&2; then
    echo "NETWORK FAIL: $name embeds URL-loading class names" >&2
    FAILURES=$((FAILURES + 1))
  fi
done

if [[ $FAILURES -gt 0 ]]; then
  echo "verify-no-network: $FAILURES failure(s)" >&2
  exit 1
fi

echo "verify-no-network: OK (no networking frameworks, symbols, or URL-loading classes)"
echo "Runtime spot-check (manual): with the app running, 'lsof -i -a -p <pid>' must print nothing."
