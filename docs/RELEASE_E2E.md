# Release end-to-end test plan

Automated checks (`make test`, `make privacy-check`, `make verify`) cover what
a machine can see. This document covers what it cannot: Gatekeeper, TCC/Input
Monitoring, Chrome Native Messaging, and absolute paths — the behaviours that
look correct on the machine that built the app and fail for a real user.

**Every public release references a completed copy of this checklist.** Copy it
into the release notes draft or `.local-project/TEST_STATUS.md` and record the
actual observations, not just ticks.

## Which scenarios apply to this release

ThoughtMeter currently ships **self-signed and not notarized**. Some checks
below only exist once releases are signed with an Apple Developer ID.

| Release type | Run |
|---|---|
| Self-signed (today) | **A** (skipping A2, A3, A6, A7, and reading A9 as "Gatekeeper prompts once; right-click → Open works"), **B**, **E** |
| First Developer ID release | **A** in full, **B**, **C**, **E** |
| Later Developer ID releases | **A** in full, **B**, **D**, **E** |

Scenario C runs exactly once — on the release that changes the signing
identity. Scenario D replaces it for every release after that.

Use a fresh macOS user account, a spare Mac, or a clean VM. Do **not** test on
the account that built the app: it holds the signing certificate and already
has TCC records, which is exactly what hides these failures.

---

## Scenario A — Clean install

Reset any prior state (test account only):

```bash
pkill ThoughtMeter 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/ThoughtMeter"
rm -f "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/org.thoughtmeter.chromehost.json"
tccutil reset All org.thoughtmeter.app
```

Download the DMG **through a browser**, from the draft release — not by copying
it out of `dist/`. Only a real download carries the quarantine attribute that
makes Gatekeeper behave the way a user will see.

| # | Step | Expected |
|---|---|---|
| A1 | `shasum -a 256 ThoughtMeter-X.Y.Z.dmg` vs `SHA256SUMS.txt` | matches exactly |
| A2 | `codesign --verify --verbose=4 ThoughtMeter-X.Y.Z.dmg` | valid signature |
| A3 | `xcrun stapler validate ThoughtMeter-X.Y.Z.dmg` | ticket present |
| A4 | `hdiutil attach …` | image contains `ThoughtMeter.app` and an `Applications` symlink |
| A5 | Drag to Applications, then `codesign -dv --verbose=4 /Applications/ThoughtMeter.app` | `Authority=Developer ID Application: …`, expected `TeamIdentifier`, `flags=…runtime`, `Timestamp=` present |
| A6 | `xcrun stapler validate /Applications/ThoughtMeter.app` | ticket present |
| A7 | `spctl --assess --type execute --verbose=4 /Applications/ThoughtMeter.app` | accepted |
| A8 | `lipo -archs` on both binaries | `arm64` |
| A9 | Double-click to launch | **launches normally** — no right-click → Open, no "unidentified developer", no Gatekeeper bypass |
| A10 | Before granting permission | app reports tracking unavailable; it must never display a healthy/counting state |
| A11 | Grant Input Monitoring via the in-app prompt | popover reads Active; menu-bar icon leaves the warning state |
| A12 | Type exactly 20 counted keystrokes in a selected app | total rises by 20 (per the counting rules in PRIVACY.md) |
| A13 | Type in an **unselected** app | no increase |
| A14 | `find "$HOME/Library/Application Support/ThoughtMeter" -maxdepth 2 -exec stat -f '%Sp %N' {} \;` | directory `drwx------`, database and `-wal`/`-shm` `-rw-------` |
| A15 | `PID=$(pgrep -x ThoughtMeter); lsof -i -a -p "$PID"` | prints nothing |

---

## Scenario B — Chrome connector

Install **ThoughtMeter Connector from the Chrome Web Store**
(`omhnbpfiapchifodmobgeglhgpgolmhn`), not an unpacked copy.

| # | Step | Expected |
|---|---|---|
| B1 | `python3 -m json.tool "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/org.thoughtmeter.chromehost.json"` | `path` is `/Applications/ThoughtMeter.app/Contents/MacOS/thoughtmeter-native-host`; `type` is `stdio` |
| B2 | Same file, `allowed_origins` | exactly `["chrome-extension://omhnbpfiapchifodmobgeglhgpgolmhn/"]` — no development origin in a clean install |
| B3 | Open the extension popup | "Connected" |
| B4 | Select `chatgpt.com` in ThoughtMeter, focus it in Chrome, type N keystrokes | that domain's count rises by N |
| B5 | Navigate to an **unselected** hostname and type | no increase |
| B6 | Focus another app while Chrome holds a tracked tab, then type | Chrome source does not accumulate |
| B7 | Quit Chrome, wait past the 3-minute freshness window, type | Chrome attribution is inactive (fails closed) |
| B8 | `grep -R -a "some-unselected-domain.com" "$HOME/Library/Application Support/ThoughtMeter"` | no match — unselected hostnames are never persisted |
| B9 | `sqlite3 <db> '.schema'` | aggregate + configuration tables only: no keycode, character, URL, page-content, or history column anywhere |

---

## Scenario C — Upgrade from a pre-Developer-ID build (0.2.x or earlier)

**The most important scenario in this document, and the one with a known,
accepted cost.**

macOS ties an Input Monitoring grant to the app's designated requirement,
which names the signing certificate. Releases up to 0.2.0 were signed with
ThoughtMeter's own self-signed certificate; the first Developer ID release
changes that leaf. The grant therefore **will not carry over** — this was
established with a negative control (see `.local-project/DECISIONS.md` D30),
so treat a surviving grant as the surprise, not the expectation.

What is being tested is not whether the grant survives. It is that the app
tells the truth about it and loses no data.

Setup: install the current public release, grant Input Monitoring, configure
one native app source and one Chrome domain, and generate history across
several minute buckets. Export a CSV as a baseline. Record the old identity:

```bash
codesign -d -r- /Applications/ThoughtMeter.app 2>&1 | tee /tmp/tm-old-requirement.txt
```

Quit ThoughtMeter. Do **not** reset TCC, delete Application Support, remove the
native-messaging manifest, or uninstall the extension. Replace only the app.

| # | Check | Required outcome |
|---|---|---|
| C1 | `codesign -d -r-` on the new app | requirement now names the Apple-issued certificate; record it next to the old one |
| C2 | Launch | **No state in which the UI claims tracking is healthy while the event tap is dead.** Either counting resumes, or the app says the permission needs re-granting |
| C3 | Expected path: permission reads as stale | popover shows the re-grant instructions; menu-bar icon shows the warning state |
| C4 | Follow those instructions (re-enable under Privacy & Security, relaunch) | counting resumes |
| C5 | Existing history | intact — totals for previous days match the CSV baseline exactly |
| C6 | Selected sources and preferences | unchanged |
| C7 | Chrome connector | reconnects; manifest still points into `/Applications`; `allowed_origins` unchanged |
| C8 | New activity | appends normally alongside the old rows |

The unacceptable outcome is silent failure: the UI looking healthy while
keystrokes never reach the counter.

---

## Scenario D — Developer ID → Developer ID continuity

This is the long-term upgrade regression, and it is what makes the promise
"future updates will not ask again" honest.

Build two candidates (for example `X.Y.Z-rc1` and `-rc2`) sharing the same
Developer ID identity, Team ID, `CFBundleIdentifier`, native host name, and
production extension ID.

| # | Step | Expected |
|---|---|---|
| D1 | Install RC1, grant Input Monitoring, confirm counting | baseline established |
| D2 | Replace with RC2 without touching System Settings | **counting resumes with no re-grant** |
| D3 | `codesign -d -r-` on both | same identity relationship; only the version differs |

A failure here means the release process is not producing a stable identity —
stop and fix it before publishing, because every future update would break
every user's grant.

---

## Scenario E — Failure injection

Deliberately break each dependency and confirm the app fails closed and says so.

| Injection | Required behaviour |
|---|---|
| Delete the native-host manifest | Connector reports disconnected; Chrome input stops counting |
| Corrupt `allowed_origins` (wrong ID) | Connector cannot connect; app fails closed rather than counting |
| Remove the native host binary | Connector reports failure; no Chrome counting |
| Launch the app directly from the mounted DMG and try to enable Chrome | registration refused with the "move to Applications" message; no manifest written |
| Move the installed app, then relaunch | manifest path repaired automatically; connector works again without manual re-registration |
| Revoke Input Monitoring while running | tap stops; UI shows the permission state; no phantom counting |
| Kill the native host process | after the documented ≤3-minute staleness window, Chrome attribution stops |
| Make the data directory read-only after launch | within ~60 s the popover reads "Active — counts are not being saved" and the icon warns; restoring write access clears it within 30 s |
| Point `THOUGHTMETER_DATA_DIR` at an unwritable path | popover and dashboard both read "Stopped — local database unavailable" |
| Malformed `CHROME_EXTENSION_ID_PROD` | build/release fails before producing artifacts |
| Developer ID certificate absent | distribution build fails; **never** falls back to ad-hoc |
| Notarization rejected, or stapling fails | release stops before checksums and before any upload |
