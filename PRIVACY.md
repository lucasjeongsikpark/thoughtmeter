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

That is the entire schema. The data directory is `0700` and the database is
`0600` — owner-only, including SQLite's `-wal` and `-shm` sidecar files,
which hold recently written rows until they are checkpointed. The app repairs
these permissions on every launch rather than only when it first creates the
files, and the test suite asserts them.

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
no update check.

Two checks back this up in CI, and it is worth being exact about what they
prove. `scripts/verify-no-network.sh` statically scans the shipped binaries
for networking frameworks, socket symbols, and URL-loading classes;
`scripts/verify-privacy.sh` scans the source for forbidden APIs and pins the
extension's permission list. Both are **guardrails, not proofs**: they catch
the ways this could plausibly regress, not every conceivable runtime
behaviour. The check anyone can run without trusting either is the direct
one — with ThoughtMeter running, `lsof -i -a -p <pid>` prints nothing.

## The Chrome extension

The optional ThoughtMeter Connector extension exists for exactly one reason:
so typing on the AI domains you selected counts, and typing everywhere else
in Chrome cannot.

- It has **no content scripts** and cannot see any page's content, your
  keystrokes, your form entries, your prompts, or model responses.
- It accesses the URL of the active tab in the currently focused Chrome
  window only long enough to reduce it to a bare hostname:
  `https://chatgpt.com/c/abc123?ref=x` becomes `chatgpt.com` immediately.
  The path, query string, fragment, and page title are discarded and never
  sent or stored.
- Only that bare hostname is sent to the local ThoughtMeter host process via
  Chrome Native Messaging (a local pipe — not a network connection).
- The host compares the hostname to your selected domains and records either
  the matched selected domain or "not tracked". **Hostnames of unselected
  sites are never written to disk.**
- If the extension is disconnected or its state is stale, Chrome input is
  simply not counted (fail closed).

### Why the Chrome Web Store listing says "Web history"

Reading the active tab's address counts as **web browsing activity** under
Google's rules, so the listing discloses it — even though ThoughtMeter only
ever keeps the hostname, and only for domains you selected.

To be precise about what that disclosure does *not* mean: the extension does
not request Chrome's `history` permission, cannot read your browsing history,
and never builds or stores a record of the pages you visit. Its entire
permission set is `tabs`, `nativeMessaging`, and `alarms` — no host
permissions, no content scripts, no `storage`.

### Chrome Web Store Limited Use

The use of information received from Google APIs will adhere to the
[Chrome Web Store User Data Policy](https://developer.chrome.com/docs/webstore/program-policies/limited-use),
including the Limited Use requirements.

ThoughtMeter uses active-tab browsing information solely to provide the
user-facing feature described above: attributing your own typing to AI
websites you explicitly selected. It is never sold, never used for
advertising, never used for creditworthiness or lending decisions, and never
transferred to a remote analytics service — there is no remote service.

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
