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

Because releases are unsigned (ad-hoc signatures), macOS may treat an updated
binary as a new app:

- You may need to approve the first launch again
  (right-click → Open, or Privacy & Security → Open Anyway).
- **Input Monitoring may need to be re-enabled.** ThoughtMeter detects this:
  the menu bar icon shows a warning state and the popover offers a shortcut
  to System Settings ▸ Privacy & Security ▸ Input Monitoring. If ThoughtMeter
  appears there but is toggled off, toggle it on; if the toggle misbehaves,
  remove ThoughtMeter from the list (–) and re-add it (+).
- If you use the Chrome extension and moved the app to a different location,
  re-register the connector in Settings ▸ Chrome.

Your recorded history is unaffected by any of this.
