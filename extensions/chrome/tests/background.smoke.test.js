// Loads the real background service worker under a stubbed `chrome` API and
// verifies it wires up correctly: listeners registered, keepalive alarm
// created, initial state sent (hostname only), popup status responses.
//
// Each test imports the worker with a unique query string so module state is
// fresh (ESM caches by full URL; the stub must be swapped in before import).
import { test } from "node:test";
import assert from "node:assert/strict";

function makeChromeStub({ hostMissing = false } = {}) {
  const registered = {
    tabsActivated: [], tabsUpdated: [], windowsFocus: [],
    alarms: [], messages: [], startup: [], installed: [],
  };
  const alarmsCreated = [];
  const postedToHost = [];
  let hostMessageListener = null;

  globalThis.chrome = {
    runtime: {
      // Mirrors real Chrome: connectNative ALWAYS returns a port, even for a
      // missing host — the failure arrives later, via onDisconnect on its
      // own task. Reporting "connected" at connect time is therefore a lie
      // the tests must be able to catch.
      connectNative: (name) => {
        let disconnectListener = null;
        const port = {
          name,
          onMessage: { addListener: (fn) => { hostMessageListener = fn; } },
          onDisconnect: { addListener: (fn) => { disconnectListener = fn; } },
          postMessage: (message) => {
            if (!hostMissing) postedToHost.push(message);
          },
        };
        if (hostMissing) {
          setTimeout(() => { if (disconnectListener) disconnectListener(); }, 0);
        }
        return port;
      },
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

const tick = (ms = 20) => new Promise((resolve) => setTimeout(resolve, ms));

test("background worker wires listeners, keepalive, and hostname-only state", async () => {
  const { registered, alarmsCreated, postedToHost, hostMessage } = makeChromeStub();
  await import("../src/background.js?healthy");
  await tick(); // initial refreshState

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

  // getStatus answers asynchronously (it refreshes state first, since the
  // popup's query may be what woke a suspended worker) and must keep the
  // response channel open. "Connected" requires the host's ack — the reply a
  // live host sends to every state message — not just a created port.
  let status;
  const keepOpen = registered.messages[0]({ type: "getStatus" }, null, (response) => { status = response; });
  assert.equal(keepOpen, true, "getStatus must return true to keep sendResponse usable");
  await tick(); // refresh sends state to the host
  hostMessage()({ type: "stateAck", tracked: true, trackedDomain: "claude.ai" }); // host answers
  await tick(); // ack settles the pending status query
  assert.ok(status, "getStatus answered after the ack");
  assert.equal(status.connected, true);
  assert.equal(status.host, "claude.ai");
  assert.equal(status.tracked, true);
  assert.equal(status.trackedDomain, "claude.ai");

  // Keepalive alarm re-sends state.
  const before = postedToHost.length;
  registered.alarms[0]({ name: "thoughtmeter-keepalive" });
  await tick();
  assert.ok(postedToHost.length > before, "keepalive re-sends state");
});

test("popup reports Not connected when the native host is missing", async () => {
  const { registered } = makeChromeStub({ hostMissing: true });
  await import("../src/background.js?host-missing");
  await tick(); // initial refresh + the async disconnect it triggers

  // Every getStatus reconnects (onDisconnect nulls the port), so each query
  // re-races Chrome's asynchronous failure delivery. The worker must wait
  // for that onDisconnect instead of trusting the freshly created port —
  // and must keep answering honestly on repeated popup opens.
  for (let attempt = 0; attempt < 2; attempt += 1) {
    let status;
    const keepOpen = registered.messages[0]({ type: "getStatus" }, null, (response) => { status = response; });
    assert.equal(keepOpen, true, "getStatus must return true to keep sendResponse usable");
    await tick(50);
    assert.ok(status, `getStatus answered (attempt ${attempt + 1})`);
    assert.equal(status.connected, false, `no ack, disconnect fired — must not claim Connected (attempt ${attempt + 1})`);
    assert.equal(status.tracked, null);
    assert.equal(status.trackedDomain, null);
  }
});
