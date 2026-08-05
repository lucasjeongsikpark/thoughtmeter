# Uninstalling ThoughtMeter

## Homebrew

```bash
brew uninstall --zap --cask thoughtmeter
```

`--zap` also removes the data folder, preferences, and the Chrome connector
manifest. Then remove the extension in Chrome (see step 5 below).

## Manual

1. **Quit ThoughtMeter** — menu bar icon → Quit. (This pauses tracking and
   flushes pending counts.)
2. **Turn off Launch at Login** if you enabled it — Settings ▸ Appearance in
   the app, or System Settings ▸ General ▸ Login Items.
3. **Remove the Chrome connector manifest** (only exists if you set up the
   extension):
   ```bash
   rm "~/Library/Application Support/Google/Chrome/NativeMessagingHosts/org.thoughtmeter.chromehost.json"
   ```
   or from a clone: `scripts/uninstall-native-host.sh`.
4. **Delete your data** (optional — skipping this keeps your history for a
   future reinstall):
   ```bash
   rm -rf "~/Library/Application Support/ThoughtMeter"
   ```
   You can also do this from inside the app first
   (Settings ▸ Data ▸ Delete All ThoughtMeter Data).
5. **Remove the Chrome extension** — `chrome://extensions` → ThoughtMeter
   Connector → Remove.
6. **Trash the app** — drag `/Applications/ThoughtMeter.app` to the Trash.
   macOS apps cannot reliably delete themselves, so this step is yours.
7. macOS cleans up the Input Monitoring entry once the app is gone; you can
   also remove it manually under System Settings ▸ Privacy & Security.

## Script

From a clone of this repository:

```bash
scripts/uninstall.sh              # removes the connector manifest, keeps data
scripts/uninstall.sh --with-data  # also deletes the data folder (asks first)
```

The script validates every path exactly before deleting and never uses broad
wildcards.
