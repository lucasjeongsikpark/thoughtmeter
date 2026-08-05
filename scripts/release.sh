#!/usr/bin/env bash
# Produce release-ready artifacts and a checklist.
# Usage: scripts/release.sh [VERSION]
# If VERSION is given it must match packaging/release-config.sh (guard against
# releasing with a stale config).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packaging/release-config.sh
source "$ROOT/packaging/release-config.sh"

REQUESTED="${1:-$VERSION}"
if [[ "$REQUESTED" != "$VERSION" ]]; then
  echo "error: requested version $REQUESTED != packaging/release-config.sh VERSION=$VERSION" >&2
  echo "Update packaging/release-config.sh first (single source of truth)." >&2
  exit 1
fi

echo "==> release $VERSION"

echo "==> working tree state"
if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then
  echo "WARNING: working tree is not clean — release artifacts will include uncommitted changes:" >&2
  git -C "$ROOT" status --short >&2
else
  echo "    clean"
fi

# Releasing ad-hoc after having released with a certificate would silently
# invalidate every existing user's Input Monitoring grant, so refuse up front
# rather than discovering it in verify (DECISIONS D30).
if [[ -n "${RELEASE_SIGN_IDENTITY:-}" ]]; then
  echo "==> signing identity"
  if security find-identity -p codesigning 2>/dev/null | grep -q "\"$RELEASE_SIGN_IDENTITY\""; then
    echo "    $RELEASE_SIGN_IDENTITY (present in keychain)"
  else
    echo "error: release signing identity '$RELEASE_SIGN_IDENTITY' is not in the keychain." >&2
    echo "Releasing ad-hoc would break the Input Monitoring grant for every existing user." >&2
    echo "Restore the certificate, or clear RELEASE_SIGN_IDENTITY deliberately." >&2
    exit 1
  fi
fi

echo "==> tests"
"$ROOT/scripts/test.sh"

echo "==> build"
"$ROOT/scripts/build.sh" release

echo "==> package"
"$ROOT/scripts/package.sh"

echo "==> verify"
"$ROOT/scripts/verify.sh"

if [[ "$CHROME_EXTENSION_ID_PROD" == "UNSET" ]]; then
  echo "NOTE: production Chrome extension ID not set — the store-installed"
  echo "      extension will not connect until it is (release-config.sh)."
fi

NOTES="$ROOT/dist/RELEASE_NOTES.md"
cat > "$NOTES" <<EOF
# ThoughtMeter v$VERSION

A lightweight, local-first macOS menu bar app that counts keystrokes inside
the AI tools and workspaces you choose. Counts, never content.

- macOS 14+ (Sonoma), Apple Silicon only
- Not notarized (no Apple Developer Program): on first launch use
  right-click → Open, or approve in System Settings → Privacy & Security
- Requires the Input Monitoring permission (counting only — key identities
  are never recorded); granting it once carries over to later versions

## Artifacts

| File | Purpose |
|---|---|
| ThoughtMeter-$VERSION.dmg | Recommended install |
| ThoughtMeter-$VERSION.zip | Alternative archive |
| thoughtmeter-extension-$EXT_VERSION.zip | Chrome Web Store upload package |
| SHA256SUMS.txt | Checksums |

Verify a download: \`shasum -a 256 --ignore-missing -c SHA256SUMS.txt\`
(\`--ignore-missing\` skips listed files you did not download.)
EOF
echo "    wrote dist/RELEASE_NOTES.md"

cat <<EOF

==> Release checklist (manual steps, see .local-project/MANUAL_ACTIONS.md)
 1. Review dist/RELEASE_NOTES.md
 2. Commit + tag:  git tag v$VERSION
 3. Push (explicitly, when ready):  git push origin main v$VERSION
 4. Create GitHub Release v$VERSION; upload ALL of:
      dist/ThoughtMeter-$VERSION.dmg
      dist/ThoughtMeter-$VERSION.zip
      dist/thoughtmeter-extension-$EXT_VERSION.zip
      dist/SHA256SUMS.txt
    (SHA256SUMS.txt references the extension zip — omitting it leaves a
    dangling checksum entry on the release page)
 5. Copy dist/thoughtmeter.rb → homebrew tap repo Casks/thoughtmeter.rb
 6. Upload dist/thoughtmeter-extension-$EXT_VERSION.zip to the Chrome Web Store
 7. After the store assigns/keeps the extension ID, confirm
    CHROME_EXTENSION_ID_PROD in packaging/release-config.sh matches
 8. Clean-machine test per docs/INSTALL.md — including the update path:
    grant Input Monitoring, replace the app with the next build, and confirm
    counting resumes without re-granting (only verified on the signing
    machine so far; see .local-project/DECISIONS.md D30)
EOF
