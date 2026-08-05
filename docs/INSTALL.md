# Installing ThoughtMeter

**Requirements:** macOS 14 (Sonoma) or later, Apple Silicon (M-series) Mac.

## Option A — Homebrew

```bash
brew install --cask jeongsikpark/thoughtmeter/thoughtmeter
```

Then start ThoughtMeter from Applications and jump to
[First launch](#first-launch) below.

## Option B — DMG

1. Download `ThoughtMeter-x.y.z.dmg` from the
   [releases page](https://github.com/jeongsikpark/thoughtmeter/releases).
2. (Optional, recommended) Verify the checksum:
   ```bash
   shasum -a 256 -c SHA256SUMS.txt
   ```
3. Open the DMG and drag **ThoughtMeter** into **Applications**.

## First launch

ThoughtMeter is open-source and currently distributed **without Apple
notarization** (that requires a paid Apple Developer membership the project
doesn't have yet). macOS will therefore block the very first open:

1. In Applications, **right-click ThoughtMeter → Open → Open**.
2. If that option doesn't appear: open the app once (it will be blocked),
   then go to **System Settings ▸ Privacy & Security**, scroll down, and
   click **Open Anyway**.

Never disable Gatekeeper or macOS security protections system-wide — no app,
including this one, should ask you to.

## Onboarding

1. **Input Monitoring** — ThoughtMeter counts keystrokes, so macOS requires
   this permission. Onboarding takes you to
   **System Settings ▸ Privacy & Security ▸ Input Monitoring**; enable
   ThoughtMeter. macOS may ask you to quit and reopen the app.
   (The permission grants the ability to observe keyboard events;
   ThoughtMeter's code only counts them — see [PRIVACY.md](../PRIVACY.md).)
2. **Pick your tools** — choose *Selected tools only* (recommended) and check
   the AI apps/domains you want, or *All recognized AI tools*.
3. **Launch at login** — optional, off by default.
4. **Chrome extension** — optional; only needed to count typing on selected
   AI websites. See [extensions/chrome/README.md](../extensions/chrome/README.md).

## Verifying it works

Type a few lines in a selected app — the menu bar count (if enabled) or the
popover total should rise within seconds. Data lives in
`~/Library/Application Support/ThoughtMeter/`.

If something is off, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
