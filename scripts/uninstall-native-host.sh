#!/usr/bin/env bash
# Remove the Chrome Native Messaging manifest. Deletes exactly one known file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

MANIFEST="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/$NATIVE_HOST_NAME.json"

# Path safety: refuse anything that is not our own manifest file.
case "$MANIFEST" in
  *"NativeMessagingHosts/$NATIVE_HOST_NAME.json") ;;
  *) echo "error: refusing to delete unexpected path: $MANIFEST" >&2; exit 1 ;;
esac

if [[ -f "$MANIFEST" ]]; then
  rm "$MANIFEST"
  echo "==> removed $MANIFEST"
else
  echo "==> nothing to remove ($MANIFEST not present)"
fi
