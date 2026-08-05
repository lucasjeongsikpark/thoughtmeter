# ThoughtMeter

**Measure the human side of AI work.**

AI systems measure everything they generate: tokens, cost, latency, and output.

ThoughtMeter measures one visible trace of the human input behind them.

It is a lightweight, local-first macOS menu bar app that counts keystrokes inside the AI tools and workspaces you choose.

> Not every keystroke is a thought. But thinking leaves traces.

<!-- screenshot: docs/assets/dashboard.png — see .local-project screenshot checklist -->

## What it does

- Counts keyboard presses **only** while an app or website you selected is frontmost — ChatGPT, Claude, VS Code, Cursor, Terminal, or `chatgpt.com` / `claude.ai` in Chrome.
- Shows a calm, native dashboard: today's Thought Input, hourly activity, per-tool breakdown, and 7/30-day trends.
- Lives in the menu bar with an optional live count (`12.4K`).
- Exports your data to CSV, renders a local **Proof of Thought** card, and deletes everything on request.
- Stores everything in one local SQLite file. **The app makes zero network requests** — no account, no telemetry, no update checks. There is even a script in this repo that verifies the binary contains no networking code.

## What "Thought Input" means

One **Thought Input keystroke** = one key transitioning into the pressed state while a selected source is frontmost. Modifier keys count once per press; auto-repeat counts; key *identities* are never read into storage — ThoughtMeter counts keyboard events, it does not record which keys you press.

## What it does not mean

ThoughtMeter deliberately does **not** measure thinking, effort, productivity, or prompt quality. If Terminal is selected, `git status` counts exactly like a carefully-composed Claude Code prompt. All keystrokes in a selected tool count toward that tool — coding, chatting, and shell commands alike. That coarseness is honest: anything finer would require reading content we do not want to read.

## Supported tools

| Kind | Recognized out of the box |
|---|---|
| AI apps | ChatGPT, Claude, Perplexity, Microsoft Copilot, Raycast, LM Studio, Ollama, Jan |
| AI-assisted editors | Visual Studio Code (+ Insiders, VSCodium), Cursor, Windsurf, Zed, Trae, Xcode, IntelliJ IDEA, PyCharm, WebStorm |
| Terminals | Terminal, iTerm2, Warp, Ghostty, Alacritty, kitty, WezTerm |
| Chrome domains | chatgpt.com, claude.ai, gemini.google.com, aistudio.google.com, notebooklm.google.com, perplexity.ai, copilot.microsoft.com, grok.com, chat.deepseek.com, chat.mistral.ai, poe.com, character.ai, meta.ai, chat.qwen.ai, kimi.com, wrtn.ai, clova-x.naver.com, v0.dev, lovable.dev, bolt.new, replit.com, midjourney.com |
| Custom | Any macOS app (picker) and any domain you add |

Only recognized apps that are actually installed on your Mac are shown, and in the default mode nothing is tracked until you explicitly select it.

Google Chrome itself cannot be added as an app — that would count typing on every website. Chrome is tracked per-domain through the extension instead.

**Requirements:** macOS 14 (Sonoma) or later, Apple Silicon.

## Installation

### Homebrew (recommended)

```bash
brew install --cask jeongsikpark/thoughtmeter/thoughtmeter
```

### Direct download

1. Download `ThoughtMeter-x.y.z.dmg` from [Releases](../../releases), and optionally verify it against `SHA256SUMS.txt` (`shasum -a 256 -c SHA256SUMS.txt`).
2. Open the DMG and drag **ThoughtMeter** to Applications.
3. First launch: ThoughtMeter is open-source and currently **not notarized** (no paid Apple Developer membership yet), so macOS will block the first open. Right-click the app → **Open** → **Open**, or approve it under **System Settings ▸ Privacy & Security**. Please don't disable Gatekeeper globally — it protects you.
4. Follow onboarding: grant **Input Monitoring** (required to count keystrokes), pick your tools, and you're done.

Full details, including why each permission is needed: [docs/INSTALL.md](docs/INSTALL.md).

## Chrome extension

Only needed if you want to count typing on selected AI websites. It reports the active tab's **hostname only** — never page content, prompts, full URLs, or history — to the local app via Chrome Native Messaging. Nothing touches the network.

Setup: [extensions/chrome/README.md](extensions/chrome/README.md) (Chrome Web Store listing coming for v0.1).

## Privacy

The one-paragraph version: ThoughtMeter stores **minute-level aggregate counts per source**, nothing else. Never key values, characters, clipboard, screenshots, window titles, URLs, page content, or history. Everything stays on your Mac until you export or delete it. The full, precise statement is in [PRIVACY.md](PRIVACY.md).

## Dashboard

- **Today** — summary cards (total, vs 7-day average, top source, peak hour), hourly chart, per-source bars, 7-day trend
- **7 Days / 30 Days** — daily totals and per-source breakdown
- **Proof of Thought** — today's trace as a 1200×630 PNG, rendered locally and saved wherever you choose

## Updating

```bash
brew update && brew upgrade --cask thoughtmeter
```

or replace the app in Applications with the new DMG's copy. Your history lives in `~/Library/Application Support/ThoughtMeter/` and survives updates. Because builds are unsigned, macOS may ask you to re-approve the app and re-grant Input Monitoring after an update — details in [docs/UPDATE.md](docs/UPDATE.md).

## Uninstalling

See [docs/UNINSTALL.md](docs/UNINSTALL.md), or run `scripts/uninstall.sh` from a clone. Homebrew users: `brew uninstall --zap --cask thoughtmeter`.

## Building from source

No Xcode required — just Command Line Tools and node:

```bash
git clone https://github.com/jeongsikpark/thoughtmeter.git
cd thoughtmeter
make bootstrap   # checks dependencies
make test        # Swift + extension tests
make dev         # build & launch a debug bundle
make package     # DMG/ZIP/checksums in dist/
```

## Contributing

Issues and PRs are very welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the architecture tour, testing expectations, and the privacy invariants every change must keep. Vulnerability reports: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE).

---

If ThoughtMeter is useful or the question behind it resonates with you, starring the repository helps other people discover it.
