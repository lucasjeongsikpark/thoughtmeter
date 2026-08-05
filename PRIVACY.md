# ThoughtMeter Privacy

ThoughtMeter counts keyboard events. It does not record which keys you press.

This document states precisely what the app observes, stores, and never does.
The codebase is small and open — every claim here can be checked against it,
and `scripts/verify-privacy.sh` / `scripts/verify-no-network.sh` enforce the
mechanical parts in CI.

## What is observed

- **Keyboard-down events**, via a listen-only macOS event tap (this is what
  the Input Monitoring permission grants). The app reads only two facts per
  event: "a key went down" and, for modifier keys, the modifier-flag bitmask
  needed to detect a press (held in memory momentarily, never stored).
- **The frontmost application's bundle identifier** (e.g. `com.apple.Terminal`).
- **The active Chrome hostname**, but only if you installed the extension —
  see below.

## What is counted

One keystroke = one supported key entering the pressed state **while a source
you selected is frontmost**. Everything else is discarded at the moment it
happens. Auto-repeat counts. Key releases do not.

## What is stored

One local SQLite file at `~/Library/Application Support/ThoughtMeter/`:

- your source list: kind (app/domain), identifier (bundle ID or domain),
  display name, enabled flag
- activity rows: **minute bucket × source × count**, with the local date and
  timezone offset of that minute

That is the entire schema. File permissions are owner-only.

## What is never stored or transmitted

Key codes. Key values. Typed characters or strings. Passwords. Prompt
contents. Clipboard contents. Pasted content. Screenshots. Audio. Page
content. Conversation content. Full URLs, URL paths, or query strings.
Browser history. Window titles. Filenames. Workspace paths. Shell commands.
Source code. Model responses. Raw keyboard event objects are never logged,
in debug builds included.

## Network behavior

**The app makes no network requests.** There is no account, no cloud, no
telemetry, no analytics SDK, no crash reporting, no remote configuration, and
no update check. `scripts/verify-no-network.sh` verifies the shipped binaries
reference no networking frameworks or URL-loading classes; you can also watch
a running instance with `lsof -i -a -p <pid>` — it prints nothing.

## The Chrome extension

The optional ThoughtMeter Connector extension exists for exactly one reason:
so typing on the AI domains you selected counts, and typing everywhere else
in Chrome cannot.

- It has **no content scripts** and cannot see any page's content, your
  keystrokes, or your history.
- It reduces the active tab's URL to a bare hostname immediately and sends
  only that hostname to the local ThoughtMeter host process via Chrome
  Native Messaging (a local pipe — not a network connection).
- The host compares the hostname to your selected domains and records either
  the matched selected domain or "not tracked". **Hostnames of unselected
  sites are never written to disk.**
- If the extension is disconnected or its state is stale, Chrome input is
  simply not counted (fail closed).

## Deletion and export

- **Settings ▸ Data ▸ Export CSV** writes the aggregate rows to a file you choose.
- **Settings ▸ Data ▸ Delete All ThoughtMeter Data** permanently removes all
  recorded history (source configuration is kept and deletable separately).
- `scripts/uninstall.sh --with-data` removes everything from disk.
- Data is retained until you delete it; there is no automatic expiry.

## Limitations to be aware of

- Keystroke counts are an imperfect trace of participation — they are not a
  measure of thinking, effort, or productivity, and ThoughtMeter never
  presents them as one.
- ThoughtMeter cannot distinguish what you typed *within* a selected tool:
  in Terminal, `git status` and a Claude Code prompt count identically.
- If the Chrome native host dies without cleanup, up to ~3 minutes of Chrome
  typing could be misattributed to the last known domain before the staleness
  window closes it.

## Intended use

ThoughtMeter is designed for voluntary personal self-tracking. Do not install
or operate it on another person's device or account without their informed
consent.
