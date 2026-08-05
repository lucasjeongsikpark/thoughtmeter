#!/usr/bin/env bash
# Privacy invariant scan. Fails if forbidden APIs or patterns appear in
# ThoughtMeter source code. This is a guardrail, not a proof — PRIVACY.md
# documents the invariants; reviewers should still read the diff.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_SOURCES=("$ROOT/apps/macos/Sources" "$ROOT/helpers/chrome-native-host/Sources")
JS_SOURCES=("$ROOT/extensions/chrome/src")
FAILURES=0

fail() {
  echo "PRIVACY FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

check_absent() {
  local pattern="$1" description="$2"; shift 2
  local hits
  hits=$(grep -rInE "$pattern" "$@" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    fail "$description"
    echo "$hits" | sed 's/^/    /' >&2
  fi
}

echo "==> scanning Swift sources"
# Typed-content capture: the app must never read key identities or characters.
check_absent 'keyboardEventKeycode|charactersIgnoringModifiers|\.characters\b|keyCode' \
  "key identity / character APIs are forbidden" "${SWIFT_SOURCES[@]}"
# Clipboard.
check_absent 'NSPasteboard|UIPasteboard' "clipboard APIs are forbidden" "${SWIFT_SOURCES[@]}"
# Screen capture / recording.
check_absent 'CGWindowListCreateImage|CGDisplayStream|AVCapture|ScreenCaptureKit|SCStream' \
  "screen capture APIs are forbidden" "${SWIFT_SOURCES[@]}"
# Networking clients.
check_absent 'URLSession|CFNetwork|NWConnection|NWListener|nw_connection|SocketPort|NSURLConnection' \
  "network client APIs are forbidden" "${SWIFT_SOURCES[@]}"
check_absent '^[[:space:]]*import[[:space:]]+Network\b' "Network.framework import is forbidden" "${SWIFT_SOURCES[@]}"
# Window titles / document introspection.
check_absent 'CGWindowListCopyWindowInfo|kCGWindowName' "window title APIs are forbidden" "${SWIFT_SOURCES[@]}"
# Analytics / crash SDKs.
check_absent 'Firebase|Sentry|Amplitude|Mixpanel|PostHog|Crashlytics|AppCenter' \
  "analytics/crash-reporting SDKs are forbidden" "${SWIFT_SOURCES[@]}" "${JS_SOURCES[@]}"

echo "==> scanning extension sources"
check_absent '\bfetch\(|XMLHttpRequest|WebSocket|EventSource\(' \
  "network calls in the extension are forbidden" "${JS_SOURCES[@]}"
check_absent 'chrome\.history|chrome\.scripting|content_scripts|chrome\.storage' \
  "history/content-script/storage APIs are forbidden in the extension" "${JS_SOURCES[@]}" "$ROOT/extensions/chrome/manifest.json"
check_absent 'document\.body|innerText|innerHTML' \
  "page-content access is forbidden in the extension background" "$ROOT/extensions/chrome/src/background.js" "$ROOT/extensions/chrome/src/lib.js"

echo "==> checking manifest permissions are minimal"
EXPECTED='"permissions": ["tabs", "nativeMessaging", "alarms"]'
if ! tr -d ' \n' < "$ROOT/extensions/chrome/manifest.json" | grep -q '"permissions":\["tabs","nativeMessaging","alarms"\]'; then
  fail "extension permissions changed — update PRIVACY.md and this check together"
fi
if grep -q 'host_permissions' "$ROOT/extensions/chrome/manifest.json"; then
  fail "host_permissions must not be requested"
fi

# Dependency hygiene: the Swift package must have zero external dependencies.
if grep -q 'dependencies:' "$ROOT/Package.swift" && grep -qE '\.package\(url' "$ROOT/Package.swift"; then
  fail "Package.swift gained an external dependency — justify and update checks"
fi

if [[ $FAILURES -gt 0 ]]; then
  echo "verify-privacy: $FAILURES failure(s)" >&2
  exit 1
fi
echo "verify-privacy: OK"
