# Troubleshooting

## macOS blocks the app on first launch

Expected — releases are not notarized (see README). Right-click the app →
**Open** → **Open**, or System Settings ▸ Privacy & Security → **Open Anyway**.
Never disable Gatekeeper globally.

## Nothing is being counted

Check, in order:

1. **Menu bar icon state** — an exclamation badge means Input Monitoring is
   missing. Open the popover for a shortcut to System Settings ▸ Privacy &
   Security ▸ Input Monitoring; enable ThoughtMeter and relaunch if asked.
2. **Is tracking paused?** The popover shows "Paused …" and offers Resume.
3. **Is the app you're typing in actually selected?** Settings ▸ Tracking —
   the toggle must be on. In *Selected tools only* mode, newly detected apps
   start off.
4. **Chrome:** typing on a website counts only if the domain is selected AND
   the extension is connected (popover shows Chrome state; also see the
   extension's own popup).

## Input Monitoring was granted but counting stopped after an update

macOS ties the grant to the app's code identity. Releases are signed with a
stable certificate specifically so that identity does not change between
versions, so this should not happen — but if it does, ThoughtMeter tells you
instead of silently recording nothing: the popover reads "Input Monitoring
lost — re-grant needed" with a shortcut button. Toggle ThoughtMeter off/on in
System Settings ▸ Privacy & Security ▸ Input Monitoring; if the toggle seems
stuck, remove the entry (–) and re-add the app (+), then relaunch. Your data
is unaffected.

Building from source? Ad-hoc signed builds pin the grant to the exact compiled
code, so **every rebuild invalidates it**. See CONTRIBUTING.md "The Input
Monitoring dev loop" for a stable identity that survives rebuilds.

## The Chrome extension says "Not connected"

1. ThoughtMeter app: Settings ▸ Chrome → **Save ID & Register** (the manifest
   must point at the app's current location — re-register after moving it).
2. `chrome://extensions` → reload the ThoughtMeter Connector.
3. Restart Chrome completely (`⌘Q`).
4. Unpacked/dev extension: its ID must be saved in Settings ▸ Chrome
   ("Save ID & Register").

## Counts look attributed to the wrong Chrome site

The extension re-sends state every minute and the app fails closed after
3 minutes of silence. If Chrome crashed mid-session a small window of typing
may have been attributed to the last known selected domain. This is bounded
by design; see PRIVACY.md "Limitations".

## The menu bar count seems behind

The popover total includes unpersisted counts and refreshes when opened.
The database itself is written in ~30-second batches — that's deliberate
(one write per keystroke would be wasteful).

## Where is my data?

`~/Library/Application Support/ThoughtMeter/ThoughtMeter.sqlite` — also
reachable via Settings ▸ Data ▸ Reveal Data Folder in Finder. It's a normal
SQLite file; inspect it with any SQLite tool. You'll find only sources and
minute-bucket counts.

## Something else

Open an issue: https://github.com/lucasjeongsikpark/thoughtmeter/issues — include
macOS version, app version (Settings ▸ About), and what you observed.
Never include personal data; ThoughtMeter has none to include.
