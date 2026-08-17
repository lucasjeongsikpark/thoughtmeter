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

## Install

From the Chrome Web Store:
<https://chromewebstore.google.com/detail/thoughtmeter-connector/omhnbpfiapchifodmobgeglhgpgolmhn>

Release builds of the macOS app already authorize the store extension, so
there is no ID to copy and nothing to configure — install it, click
**Register Connector** in the app's Settings ▸ Chrome, then quit and reopen
Chrome so it picks up the connector registration.

Contributors running this extension from source: see
[CONTRIBUTING.md](../../CONTRIBUTING.md), "Developing the Chrome extension".

## Tests

```bash
npm test   # node --test, no dependencies
```
