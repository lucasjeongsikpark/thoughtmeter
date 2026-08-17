# Updating ThoughtMeter

ThoughtMeter performs **no update checks** — it will never phone home to ask
about versions. New releases are announced only on the GitHub repository.

Your history is stored in `~/Library/Application Support/ThoughtMeter/`,
outside the app bundle, so **updates never touch your data**.

## Homebrew

```bash
brew update
brew upgrade --cask thoughtmeter
```

## Manual (DMG)

1. Quit ThoughtMeter (menu bar icon → Quit).
2. Download the latest DMG from the releases page.
3. Open the DMG and drag ThoughtMeter to Applications, replacing the old copy.
4. Reopen ThoughtMeter.

## After updating: permissions

Releases are **not notarized**, so macOS may ask you to approve the app again
on first launch: open it once, then System Settings ▸ Privacy & Security →
**Open Anyway** → confirm and authenticate. On macOS 14 (Sonoma) only,
right-click → **Open** → **Open** is a one-step equivalent; macOS 15 and later
removed it. See [INSTALL.md](INSTALL.md#first-launch) for the full steps.

**Input Monitoring normally carries over.** Releases are signed with a stable
certificate, which keeps the app's code identity the same from version to
version, so macOS recognises the updated app as the one you already approved.

If counting does stop after an update, ThoughtMeter tells you rather than
silently recording nothing: the menu bar icon shows a warning state and the
popover reads "Input Monitoring lost — re-grant needed" with a shortcut to
System Settings ▸ Privacy & Security ▸ Input Monitoring. Toggle ThoughtMeter
on there; if the toggle misbehaves, remove the entry (–) and re-add it (+).

If you use the Chrome extension and moved the app to a different location,
re-register the connector in Settings ▸ Chrome.

Your recorded history is unaffected by any of this.
