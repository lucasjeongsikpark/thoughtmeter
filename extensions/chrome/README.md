# ThoughtMeter Connector (Chrome extension)

Links Google Chrome to the ThoughtMeter macOS app so typing on the AI
websites you selected (for example `chatgpt.com` and `claude.ai`) can be
counted — and typing everywhere else in Chrome cannot.

## What it does

1. Watches which tab is active (tab switch, navigation, window focus).
2. Reduces the active tab's URL to a bare hostname immediately.
3. Sends that hostname to the local ThoughtMeter native messaging host.
4. The host compares it against the domains you selected in the app and
   records either the matched selected domain or "not tracked" — never the
   raw hostname of an unselected site.

## What it never does

- No content scripts — it cannot see any page's content.
- It never sees which keys you press (that is the macOS app, and even the
  app only counts events, never key identities).
- No full URLs, paths, queries, or titles — hostname only.
- No browsing history, no storage of visited sites.
- No network communication of any kind. The only channel is Chrome
  Native Messaging to the local ThoughtMeter host process.

## Permissions

| Permission | Why |
|---|---|
| `tabs` | Read the active tab's URL to derive its hostname. |
| `nativeMessaging` | Talk to the local ThoughtMeter app. |
| `alarms` | Once-a-minute keepalive so the app can treat silence as "disconnected" and stop counting (fail closed). |

## Development install

1. Build and run the ThoughtMeter app once (`make dev` in the repo root).
2. `chrome://extensions` → enable Developer mode → "Load unpacked" → select
   this `extensions/chrome/` directory.
3. Copy the extension ID Chrome assigned.
4. In ThoughtMeter: Settings ▸ Chrome → paste the ID → "Save ID & Register".
   (Or run `scripts/install-native-host.sh --dev-id <ID>` from the repo root.)
5. Reload the extension. The popup should show "Connected".

## Tests

```bash
npm test   # node --test, no dependencies
```
