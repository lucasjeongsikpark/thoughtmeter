// Loads the real background service worker under a stubbed `chrome` API and
// verifies it wires up correctly: listeners registered, keepalive alarm
// created, initial state sent (hostname only), popup status responses.
import { test } from "node:test";
import assert from "node:assert/strict";

function makeChromeStub() {
  const registered = {
    tabsActivated: [], tabsUpdated: [], windowsFocus: [],
    alarms: [], messages: [], startup: [], installed: [],
  };
  const alarmsCreated = [];
  const postedToHost = [];
  let hostMessageListener = null;

  globalThis.chrome = {
    runtime: {
      connectNative: (name) => ({
        name,
        onMessage: { addListener: (fn) => { hostMessageListener = fn; } },
        onDisconnect: { addListener: () => {} },
        postMessage: (message) => postedToHost.push(message),
      }),
      onMessage: { addListener: (fn) => registered.messages.push(fn) },
      onStartup: { addListener: (fn) => registered.startup.push(fn) },
      onInstalled: { addListener: (fn) => registered.installed.push(fn) },
    },
    tabs: {
      onActivated: { addListener: (fn) => registered.tabsActivated.push(fn) },
      onUpdated: { addListener: (fn) => registered.tabsUpdated.push(fn) },
      query: async () => [{ active: true, url: "https://claude.ai/chat/very-private-path?q=secret" }],
    },
    windows: {
      onFocusChanged: { addListener: (fn) => registered.windowsFocus.push(fn) },
      getLastFocused: async () => ({ id: 1, focused: true }),
    },
    alarms: {
      create: (name, info) => alarmsCreated.push({ name, info }),
      onAlarm: { addListener: (fn) => registered.alarms.push(fn) },
    },
  };
  return { registered, alarmsCreated, postedToHost, hostMessage: () => hostMessageListener };
}

test("background worker wires listeners, keepalive, and hostname-only state", async () => {
  const { registered, alarmsCreated, postedToHost, hostMessage } = makeChromeStub();
  await import("../src/background.js");
  await new Promise((resolve) => setTimeout(resolve, 20)); // initial refreshState

  // Event wiring.
  assert.equal(registered.tabsActivated.length, 1, "tabs.onActivated wired");
  assert.equal(registered.tabsUpdated.length, 1, "tabs.onUpdated wired");
  assert.equal(registered.windowsFocus.length, 1, "windows.onFocusChanged wired");
  assert.equal(registered.messages.length, 1, "popup message handler wired");
  assert.equal(registered.alarms.length, 1, "alarm handler wired");

  // Keepalive alarm: 1 minute, matching the app's 3-minute staleness window.
  assert.deepEqual(alarmsCreated[0], {
    name: "thoughtmeter-keepalive",
    info: { periodInMinutes: 1 },
  });

  // Initial state was sent, reduced to the hostname — never the URL.
  assert.ok(postedToHost.length >= 1, "initial state sent to host");
  assert.deepEqual(postedToHost.at(-1), { type: "state", host: "claude.ai" });
  const wire = JSON.stringify(postedToHost);
  assert.ok(!wire.includes("very-private-path"), "URL path must never reach the host");
  assert.ok(!wire.includes("secret"), "query string must never reach the host");

  // Host ack updates popup status. getStatus answers asynchronously (it
  // refreshes state first, since the popup's query may be what woke a
  // suspended worker) and must keep the response channel open.
  hostMessage()({ type: "stateAck", tracked: true, trackedDomain: "claude.ai" });
  let status;
  const keepOpen = registered.messages[0]({ type: "getStatus" }, null, (response) => { status = response; });
  assert.equal(keepOpen, true, "getStatus must return true to keep sendResponse usable");
  await new Promise((resolve) => setTimeout(resolve, 20)); // refresh completes, then responds
  assert.equal(status.connected, true);
  assert.equal(status.host, "claude.ai");
  assert.equal(status.tracked, true);
  assert.equal(status.trackedDomain, "claude.ai");

  // Keepalive alarm re-sends state.
  const before = postedToHost.length;
  registered.alarms[0]({ name: "thoughtmeter-keepalive" });
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.ok(postedToHost.length > before, "keepalive re-sends state");
});
