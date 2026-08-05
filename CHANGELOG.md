# Changelog

All notable changes to ThoughtMeter are documented here.
Format: [Keep a Changelog](https://keepachangelog.com); versions follow SemVer.

## [Unreleased]

The Chrome extension is bumped to 0.1.2 (its versioning is independent of
the app's — see the first entry).

### Fixed
- The extension popup no longer claims "Connected" when the native host is
  missing or unreachable. Chrome reports that failure asynchronously, so the
  worker treated every freshly created port as connected — the popup, the
  exact place the install docs send you to diagnose the chain, could never
  say "Not connected". A connection now counts only once the host actually
  replies, and the popup waits briefly for that proof (extension 0.1.2).
- The dashboard's Share button now disables when **today** is empty. The
  card always renders today's numbers, but the button checked the selected
  range — with 7/30 Days selected and history present, it happily exported
  a "Today's Thought Input — 0 keystrokes" card.
- If the local database fails to open, the dashboard says so (matching the
  menu bar popover) instead of advising you to "start typing in a selected
  tool" — advice that cannot work while nothing is being recorded.
- Onboarding resumes at the step you were on after a quit-and-reopen, which
  its Input Monitoring step has promised all along (macOS can require a
  relaunch mid-grant).
- The menu bar popover reports a failed database open as "Stopped — local
  database unavailable" plus the underlying error, instead of a misleading
  "Input Monitoring needed".
- A development extension ID must look like one (32 letters a–p) before it
  reaches the native-messaging manifest — Chrome rejects the entire manifest
  over one malformed entry, severing the store extension's connection too.
  Enforced in Settings ▸ Chrome and now also in
  `scripts/install-native-host.sh --dev-id`.
- `scripts/verify-no-network.sh` fails closed: a missing or unreadable
  binary fails the scan instead of passing every check vacuously.
- `--render-previews` exits nonzero when a render or write fails instead of
  printing success, and its 7-day sample is arithmetically consistent (the
  "Total (7 Days)" card used to disagree with its own by-day chart).
- Generated Xcode projects build again: `project.yml` set
  `SWIFT_VERSION: 5.9`, which Xcode rejects (valid language modes are
  4.0 / 4.2 / 5.0 / 6.0).
- Download-verification commands in README and docs/INSTALL work when only
  some release assets were downloaded (`--ignore-missing`).

## [0.1.2] — 2026-08-05

Bug-fix release: every defect found in a full-repository audit.
The Chrome extension is updated separately (its 0.1.1 fixes the popup
showing a stale "Not connected" right after waking).

### Fixed
- Counts drained for a flush are no longer lost if the database write fails
  (disk full, I/O error): they merge back into memory and retry on the next
  cycle, as the surrounding code always claimed. A keystroke recorded in the
  instant between removing a source and re-resolving no longer aborts the
  whole batch.
- The "Proof of Thought" card always renders **today's** numbers, as its
  headline says — previously, sharing while the dashboard showed 7 or
  30 Days exported the multi-day total labeled "Today's Thought Input".
- "vs 7-day average" now really averages the 7 days ending yesterday
  (it silently used only 6).
- With two or more Chrome profiles running the extension, the unfocused
  profile's keepalive no longer erases the focused profile's tracked state,
  which silently paused Chrome counting for most of every minute.
- The native host now records the disconnect state even when Chrome closes
  the pipe mid-write (previously SIGPIPE killed it first).
- The extension popup no longer shows a stale "Not connected" when its own
  opening is what woke the service worker; it refreshes before answering.
- Database read errors mid-query are reported instead of silently returning
  truncated results (worst case was an incomplete CSV export saved as a
  "successful" backup).
- A failed "Save Image…" of the share card now shows an error instead of
  closing the dialog as if it had saved.
- Counts crossing 999,950 display as "1M" in the menu bar, not "1000K".
- Custom-domain input like `example.com/login?next=https://evil.com` now
  parses as `example.com` instead of registering the embedded URL's host.
- Docs: the manual uninstall commands now expand `~` correctly (the data
  folder deletion previously deleted nothing while appearing to succeed);
  Settings ▸ Chrome button referenced by its real label; download
  verification command works when only some assets were downloaded.

## [0.1.1] — 2026-08-05

### Fixed
- **v0.1.0 crashed at launch on every machine except the one that built it.**
  The Swift Package Manager resource-bundle accessor looks for the domain-icon
  bundle at the app root and at the build machine's absolute `.build` path —
  never in `Contents/Resources`, where the build installs it. On the build
  machine the `.build` fallback silently masked the bug; everywhere else the
  app hit `Fatal error: could not load resource bundle` as soon as a domain
  icon rendered. Icons now resolve from the app's own Resources directory, a
  missing bundle degrades to monogram icons instead of crashing, and
  `make verify` now launches the app with the build-directory fallback masked
  so this class of bug cannot pass verification again.

### Added
- The app now knows the Chrome Web Store extension ID, so the store-installed
  ThoughtMeter Connector is accepted without pasting an ID into Settings.

## [0.1.0] — 2026-08-04 (Public Beta)

First public release.

### Added
- macOS menu bar app (Apple Silicon, macOS 14+) counting keyboard-down events
  inside user-selected AI tools and workspaces — the **Thought Input** metric.
- Two tracking modes: *Selected tools only* (default) and *All recognized AI tools*.
- Recognized catalog (verified against installed bundles at runtime):
  AI apps (ChatGPT, Claude, Perplexity, Microsoft Copilot, Grok, Raycast,
  LM Studio, Ollama, Jan), AI-assisted editors (VS Code family, Cursor, Windsurf, Zed,
  Trae, Xcode, IntelliJ IDEA, PyCharm, WebStorm), and terminals (Terminal,
  iTerm2, Warp, Ghostty, Alacritty, kitty, WezTerm); custom apps and domains.
- Chrome domain tracking via a Manifest V3 extension + local Native Messaging
  host, with 22 recognized AI domains (ChatGPT, Claude, Gemini, Perplexity,
  Copilot, Grok, DeepSeek, Le Chat, Poe, Character.AI, Meta AI, Qwen, Kimi,
  Wrtn, CLOVA X, v0, Lovable, Bolt, Replit, Midjourney, AI Studio, NotebookLM)
  plus custom domains. Hostname-only; fail-closed staleness.
- Source icons throughout (popover, dashboard, settings) and an icon +
  labeled-bar source breakdown on the dashboard. Recognized domains show
  their real service favicon (bundled at build time — the app never fetches
  anything at runtime; see NOTICE); custom domains get a stable monogram.
- "Proof of Thought": today's trace exported locally as a 1200×630 PNG.
- Dashboard: Today / 7 Days / 30 Days, hourly chart, per-source breakdown,
  7-day trend, empty states.
- Menu bar popover with live count, top-3 sources, pause controls
  (15 min / 1 h / until tomorrow / indefinite).
- Configurable menu bar display (icon only / compact / exact / hidden count).
- Six-step onboarding with explicit source confirmation and permission guidance.
- Local share-card PNG export (1200×630), CSV export, delete-all-data,
  launch-at-login (opt-in), uninstall script.
- Privacy guardrails: `make privacy-check` source scan and a binary
  no-network verification; minute-bucketed aggregate-only SQLite storage.

### Security / privacy
- No network code, no telemetry, no analytics, no update checks.
- **Not notarized** (no Apple Developer Program) — first launch requires
  right-click → Open; the caveat is documented rather than worked around, and
  users are never told to disable Gatekeeper.
- Signed with a stable certificate so macOS keeps recognising the app across
  versions: Input Monitoring is granted once and carries over to updates,
  instead of silently breaking every time the app changes.
