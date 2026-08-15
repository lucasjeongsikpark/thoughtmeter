#!/usr/bin/env bash
# Register the Chrome Native Messaging manifest so the ThoughtMeter Connector
# extension can reach the local host binary inside the app bundle.
#
# Usage:
#   scripts/install-native-host.sh [--app <path-to-ThoughtMeter.app>] [--dev-id <extension-id>]
#
# Without --app, searches: /Applications, ./dist, ./.build/dev.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

APP=""
DEV_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)    APP="$2"; shift 2 ;;
    --dev-id) DEV_ID="$2"; shift 2 ;;
    *) echo "error: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

if [[ -z "$APP" ]]; then
  for candidate in "/Applications/ThoughtMeter.app" "$ROOT/dist/ThoughtMeter.app" "$ROOT/.build/dev/ThoughtMeter.app"; do
    if [[ -d "$candidate" ]]; then APP="$candidate"; break; fi
  done
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: ThoughtMeter.app not found. Build it (make build) or pass --app <path>." >&2
  exit 1
fi

# Chrome requires the manifest's "path" to be absolute on macOS (relative is a
# Windows-only allowance) — a relative --app would register fine and then fail
# only as "Not connected" in the extension. A quote or backslash in the path
# would invalidate the manifest JSON as a whole, store origin included.
APP="$(cd "$APP" && pwd)"
if [[ "$APP" == *'"'* || "$APP" == *'\'* ]]; then
  echo "error: app path contains a character (\" or \\) that cannot be written into the manifest JSON:" >&2
  echo "  $APP" >&2
  echo "  Move the app to a plainly named directory and re-run. Nothing was changed." >&2
  exit 1
fi

HOST_BINARY="$APP/Contents/MacOS/thoughtmeter-native-host"
if [[ ! -x "$HOST_BINARY" ]]; then
  echo "error: native host binary missing at $HOST_BINARY" >&2
  exit 1
fi

# Chrome treats allowed_origins as all-or-nothing: one malformed origin
# invalidates the ENTIRE manifest, severing the store extension too. Same
# gate the app applies in Settings (extension IDs are exactly 32 of a-p).
if [[ -n "$DEV_ID" && ! "$DEV_ID" =~ ^[a-p]{32}$ ]]; then
  echo "error: --dev-id '$DEV_ID' is not a valid Chrome extension ID (exactly 32 letters a-p)." >&2
  echo "  Copy it from chrome://extensions (Developer mode on). Nothing was changed." >&2
  exit 1
fi

ORIGINS=()
if [[ "$CHROME_EXTENSION_ID_PROD" != "UNSET" && -n "$CHROME_EXTENSION_ID_PROD" ]]; then
  # Same gate as the dev ID above. release-config.sh already refuses to load a
  # malformed production ID; re-checking here keeps the guarantee local to the
  # script that actually writes the manifest.
  if [[ ! "$CHROME_EXTENSION_ID_PROD" =~ ^[a-p]{32}$ ]]; then
    echo "error: CHROME_EXTENSION_ID_PROD '$CHROME_EXTENSION_ID_PROD' is not a valid Chrome extension ID (exactly 32 letters a-p)." >&2
    echo "  Fix packaging/release-config.sh. Nothing was changed." >&2
    exit 1
  fi
  ORIGINS+=("chrome-extension://$CHROME_EXTENSION_ID_PROD/")
fi
if [[ -n "$DEV_ID" ]]; then
  ORIGINS+=("chrome-extension://$DEV_ID/")
fi
if [[ ${#ORIGINS[@]} -eq 0 ]]; then
  echo "error: no extension ID available." >&2
  echo "  For development: pass --dev-id <id> (from chrome://extensions, Developer mode)." >&2
  echo "  For release: set CHROME_EXTENSION_ID_PROD in packaging/release-config.sh." >&2
  exit 1
fi

ORIGINS_JSON=""
for origin in "${ORIGINS[@]}"; do
  [[ -n "$ORIGINS_JSON" ]] && ORIGINS_JSON+=", "
  ORIGINS_JSON+="\"$origin\""
done

MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST="$MANIFEST_DIR/$NATIVE_HOST_NAME.json"
mkdir -p "$MANIFEST_DIR"

cat > "$MANIFEST" <<EOF
{
  "name": "$NATIVE_HOST_NAME",
  "description": "ThoughtMeter native messaging host (local only)",
  "path": "$HOST_BINARY",
  "type": "stdio",
  "allowed_origins": [$ORIGINS_JSON]
}
EOF
chmod 600 "$MANIFEST"

echo "==> registered $MANIFEST"
echo "    host binary: $HOST_BINARY"
echo "    origins: ${ORIGINS[*]}"
echo "Restart Chrome (or reload the extension) to pick this up."
