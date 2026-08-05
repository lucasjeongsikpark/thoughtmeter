# Changelog

All notable changes to ThoughtMeter are documented here.
Format: [Keep a Changelog](https://keepachangelog.com); versions follow SemVer.

## [0.1.0] — unreleased (Public Beta)

First public release.

### Added
- macOS menu bar app (Apple Silicon, macOS 14+) counting keyboard-down events
  inside user-selected AI tools and workspaces — the **Human Input** metric.
- Two tracking modes: *Selected tools only* (default) and *All recognized AI tools*.
- Recognized catalog (verified against installed bundles at runtime):
  AI apps (ChatGPT, Claude, Perplexity, Microsoft Copilot, Raycast, LM Studio,
  Ollama, Jan), AI-assisted editors (VS Code family, Cursor, Windsurf, Zed,
  Trae, Xcode, IntelliJ IDEA, PyCharm, WebStorm), and terminals (Terminal,
  iTerm2, Warp, Ghostty, Alacritty, kitty, WezTerm); custom apps and domains.
- Chrome domain tracking via a Manifest V3 extension + local Native Messaging
  host, with 22 recognized AI domains (ChatGPT, Claude, Gemini, Perplexity,
  Copilot, Grok, DeepSeek, Le Chat, Poe, Character.AI, Meta AI, Qwen, Kimi,
  Wrtn, CLOVA X, v0, Lovable, Bolt, Replit, Midjourney, AI Studio, NotebookLM)
  plus custom domains. Hostname-only; fail-closed staleness.
- Source icons throughout (popover, dashboard, settings) and an icon +
  labeled-bar source breakdown on the dashboard. Domains show the companion
  desktop app's icon when installed, otherwise a stable colored monogram
  (favicons are never fetched — no network requests).
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
- Distributed unsigned (ad-hoc signature) — not notarized; documented
  first-launch and update caveats.
