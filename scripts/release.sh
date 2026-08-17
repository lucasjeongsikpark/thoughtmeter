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

DISTRIBUTION="${TM_DISTRIBUTION_BUILD:-0}"

if [[ "$DISTRIBUTION" == "1" ]]; then
  echo "==> release $VERSION (DISTRIBUTION: Developer ID + notarization)"
else
  echo "==> release $VERSION"
fi

echo "==> working tree state"
# Hard failure, not a warning: a release artifact whose contents cannot be
# traced to a specific commit is unauditable after the fact, and the warning
# was easy to scroll past in a long release log.
#
# git's own errors are a failure too, not silence. Discarding them (as a bare
# `2>/dev/null` would) turns "not a repository", "dubious ownership", or a
# missing git into empty output — which reads as a clean tree.
if ! tree_state="$(git -C "$ROOT" status --porcelain 2>&1)"; then
  echo "error: could not read the working tree state — refusing to build release artifacts" >&2
  echo "$tree_state" >&2
  exit 1
fi
if [[ -n "$tree_state" ]]; then
  echo "error: working tree is not clean — refusing to build release artifacts" >&2
  echo "  Artifacts must correspond exactly to a commit. Commit or stash first:" >&2
  echo "$tree_state" >&2
  exit 1
fi
echo "    clean"

if [[ "$DISTRIBUTION" == "1" ]]; then
  # build.sh re-validates these; failing here keeps the tests from running for
  # ten minutes before the release stops on missing credentials.
  : "${TM_SIGN_IDENTITY:?TM_SIGN_IDENTITY is required for a distribution release (Developer ID Application identity)}"
  : "${TM_APPLE_TEAM_ID:?TM_APPLE_TEAM_ID is required for a distribution release}"
  echo "==> signing identity"
  echo "    $TM_SIGN_IDENTITY (team $TM_APPLE_TEAM_ID)"
elif [[ -n "${RELEASE_SIGN_IDENTITY:-}" ]]; then
  # Releasing ad-hoc after having released with a certificate would silently
  # invalidate every existing user's Input Monitoring grant, so refuse up front
  # rather than discovering it in verify (DECISIONS D30).
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

if [[ "$DISTRIBUTION" == "1" ]]; then
  # Order is load-bearing: the ticket is stapled to the .app, so the app must
  # be notarized BEFORE it is copied into the DMG and ZIP; and the DMG's own
  # ticket changes its bytes, so checksums come last (scripts/finalize-dist.sh).
  echo "==> notarize app"
  "$ROOT/scripts/notarize-app.sh"

  echo "==> package"
  "$ROOT/scripts/package.sh"

  echo "==> notarize DMG"
  "$ROOT/scripts/notarize-dmg.sh"

  echo "==> verify (distribution)"
  "$ROOT/scripts/verify-distribution.sh"

  echo "==> finalize (checksums + cask from the stapled artifacts)"
  "$ROOT/scripts/finalize-dist.sh"
else
  echo "==> package"
  "$ROOT/scripts/package.sh"

  echo "==> verify"
  "$ROOT/scripts/verify.sh"
fi

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
EOF

if [[ "$DISTRIBUTION" == "1" ]]; then
  cat >> "$NOTES" <<EOF
- Signed with ThoughtMeter's Apple Developer ID and notarized by Apple:
  open the disk image and drag the app to Applications — no right-click → Open,
  and nothing to approve in Privacy & Security to launch it
- Requires the Input Monitoring permission (counting only — key identities are
  never recorded)

### Upgrading from 0.2.x or earlier

Those builds were signed with ThoughtMeter's own certificate rather than an
Apple-issued one. macOS ties an Input Monitoring grant to the exact signing
identity, so this update needs the permission granted **once more**:

1. Open System Settings ▸ Privacy & Security ▸ Input Monitoring.
2. Re-enable ThoughtMeter (remove and re-add it if the toggle looks stuck).
3. Relaunch ThoughtMeter.

Your history, selected sources, and Chrome setup are untouched — this is a
permission record, not your data. ThoughtMeter shows the exact repair steps in
its popover if it detects the stale grant, and future updates signed with the
same Developer ID will not ask again.
EOF
else
  cat >> "$NOTES" <<EOF
- Not notarized (no Apple Developer Program): approve the first launch once —
  open the app, click Done, then System Settings ▸ Privacy & Security →
  **Open Anyway**. (On macOS 14 Sonoma only, right-click → Open also works;
  macOS 15 removed that shortcut.) Full steps: the README's "First launch"
- Requires the Input Monitoring permission (counting only — key identities
  are never recorded); granting it once carries over to later versions
EOF
fi

cat >> "$NOTES" <<EOF

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
    ONLY if the extension itself changed — a re-upload restarts store review
 7. After the store assigns/keeps the extension ID, confirm
    CHROME_EXTENSION_ID_PROD in packaging/release-config.sh matches
 8. Run docs/RELEASE_E2E.md and attach the completed checklist
EOF

if [[ "$DISTRIBUTION" == "1" ]]; then
  cat <<EOF
 9. This is a Developer-ID release: E2E scenario C (upgrade from a
    pre-Developer-ID build) is REQUIRED — confirm the one-time Input
    Monitoring re-grant is prompted clearly and that history survives it
EOF
fi
