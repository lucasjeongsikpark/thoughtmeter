#!/usr/bin/env bash
# Run all automated tests: Swift (custom runner) + Chrome extension (node).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Swift tests"
swift run --package-path "$ROOT" thoughtmeter-tests

echo "==> Chrome extension tests"
(cd "$ROOT/extensions/chrome" && node --test tests/*.test.js)

echo "==> all tests passed"
