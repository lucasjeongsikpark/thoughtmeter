# Changelog

All notable changes to ThoughtMeter are documented here.
Format: [Keep a Changelog](https://keepachangelog.com); versions follow SemVer.

## [0.1.0] — unreleased (Public Beta)

First public release.

### Added
- macOS menu bar app (Apple Silicon, macOS 14+) counting keyboard-down events
  inside user-selected AI tools and workspaces — the **Human Input** metric.
- Two tracking modes: *Selected tools only* (default) and *All recognized AI tools*.
- Recognized apps: ChatGPT, Claude, VS Code, Cursor, Terminal, iTerm2, Warp,
  Zed, Windsurf (verified against installed bundles); custom apps and domains.
- Chrome domain tracking (`chatgpt.com`, `claude.ai`, custom) via a Manifest V3
  extension + local Native Messaging host. Hostname-only; fail-closed staleness.
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
- Distributed unsigned (ad-hoc signature) — not notarized; documented
  first-launch and update caveats.
