#!/usr/bin/env bash
# Build a debug bundle and launch it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/build.sh" debug
echo "==> launching"
open "$ROOT/.build/dev/ThoughtMeter.app"
