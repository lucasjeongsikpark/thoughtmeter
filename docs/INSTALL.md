# Installing ThoughtMeter

**Requirements:** macOS 14 (Sonoma) or later, Apple Silicon (M-series) Mac.

## Option A — Homebrew

```bash
brew install --cask lucasjeongsikpark/thoughtmeter/thoughtmeter
```

Homebrew 6.0 and later refuse to load casks from third-party taps until you
trust them, so you may see `Refusing to load cask … from untrusted tap`. That
is Homebrew asking you to confirm you meant to install from outside the
official repositories. To proceed:

```bash
brew trust lucasjeongsikpark/thoughtmeter
```

then run the install again. (`brew untrust` reverses it. On Homebrew 5 and
earlier there is no `brew trust` command and none of this applies.)

Then start ThoughtMeter from Applications and jump to
[First launch](#first-launch) below.

## Option B — DMG

1. Download `ThoughtMeter-x.y.z.dmg` from the
   [releases page](https://github.com/lucasjeongsikpark/thoughtmeter/releases).
2. (Optional, recommended) Download `SHA256SUMS.txt` from the same release
   and verify the checksum:
   ```bash
   shasum -a 256 --ignore-missing -c SHA256SUMS.txt
   ```
   (`--ignore-missing` skips listed files you did not download — without it
   the command fails because the checksum file also lists the other release
   artifacts.)
3. Open the DMG and drag **ThoughtMeter** into **Applications**.

## First launch

ThoughtMeter is open-source and currently distributed **signed but without
Apple notarization** (notarization requires a paid Apple Developer membership
the project doesn't have yet). macOS will therefore block the very first open.
These steps work on every supported macOS version, and apply to both install
methods above:

1. Open **ThoughtMeter** from Applications. macOS says *"Apple could not
   verify 'ThoughtMeter' is free of malware…"* — click **Done**. Do **not**
   click *Move to Trash*.
2. Open **System Settings ▸ Privacy & Security** and scroll down to the
   **Security** section. Next to the line reading **"ThoughtMeter" was blocked
   to protect your Mac**, click **Open Anyway**. The button appears only after one blocked
   open attempt, so don't skip step 1.
3. Confirm **Open Anyway** in the dialog and authenticate with Touch ID or
   your login password.

You approve each downloaded version once; normal launches afterwards are
unaffected.

On **macOS 14 (Sonoma) only**, right-clicking the app in Applications and
choosing **Open → Open** does the same thing in one step. macOS 15 (Sequoia)
and later removed that shortcut, which is why the System Settings path above
is the primary one.

Never disable Gatekeeper or macOS security protections system-wide — no app,
including this one, should ask you to.

## Onboarding

ThoughtMeter is a menu bar app with no Dock icon: after this first run you
find it by its icon at the top right of the screen, not in the Dock or with
⌘-Tab. Onboarding opens by itself on first launch.

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
   AI websites. Install **ThoughtMeter Connector** from the
   [Chrome Web Store](https://chromewebstore.google.com/detail/thoughtmeter-connector/omhnbpfiapchifodmobgeglhgpgolmhn),
   click **Register Connector** in **Settings ▸ Chrome**, then quit and reopen
   Chrome. What the extension does and doesn't do:
   [extensions/chrome/README.md](../extensions/chrome/README.md).

## Verifying it works

Type a few lines in a selected app — the menu bar count (if enabled) or the
popover total should rise within seconds. Data lives in
`~/Library/Application Support/ThoughtMeter/`.

If something is off, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
