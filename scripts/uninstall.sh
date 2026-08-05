#!/usr/bin/env bash
# Safe user-facing uninstall helper. See docs/UNINSTALL.md for the manual path.
#
# Removes, with confirmation and exact path validation:
#   1. the Chrome Native Messaging manifest
#   2. ThoughtMeter's data folder (only with --with-data)
# It does NOT delete ThoughtMeter.app — drag it to the Trash yourself
# (macOS apps cannot reliably delete themselves).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_DATA=0
[[ "${1:-}" == "--with-data" ]] && WITH_DATA=1

echo "ThoughtMeter uninstall helper"
echo
echo "Before running this, please quit ThoughtMeter (menu bar icon → Quit)"
echo "and, if you enabled it, turn off Launch at Login in Settings ▸ Appearance"
echo "(or System Settings ▸ General ▸ Login Items)."
echo

# 1. Native messaging manifest.
"$ROOT/scripts/uninstall-native-host.sh"

# 2. Data folder (opt-in).
DATA_DIR="$HOME/Library/Application Support/ThoughtMeter"
if [[ $WITH_DATA -eq 1 ]]; then
  # Exact path validation — refuse anything unexpected.
  case "$DATA_DIR" in
    "$HOME/Library/Application Support/ThoughtMeter") ;;
    *) echo "error: refusing to delete unexpected path: $DATA_DIR" >&2; exit 1 ;;
  esac
  if [[ -d "$DATA_DIR" ]]; then
    echo "About to permanently delete all ThoughtMeter history and settings data:"
    echo "    $DATA_DIR"
    read -r -p "Type 'delete' to confirm: " answer
    if [[ "$answer" == "delete" ]]; then
      rm -rf "$DATA_DIR"
      echo "==> removed $DATA_DIR"
    else
      echo "==> skipped data deletion"
    fi
  else
    echo "==> no data folder present"
  fi
else
  echo "==> keeping data folder ($DATA_DIR). Re-run with --with-data to remove it."
fi

# Preferences (best effort, tiny plist).
defaults delete org.thoughtmeter.app >/dev/null 2>&1 || true

cat <<'EOF'

Remaining manual steps:
  1. Drag ThoughtMeter.app from /Applications to the Trash.
  2. Remove the ThoughtMeter Connector extension in Chrome
     (chrome://extensions → Remove).
  3. Optionally remove ThoughtMeter from System Settings ▸ Privacy & Security
     ▸ Input Monitoring (macOS clears this when the app is gone).

Homebrew users can instead run:  brew uninstall --zap --cask thoughtmeter
EOF
