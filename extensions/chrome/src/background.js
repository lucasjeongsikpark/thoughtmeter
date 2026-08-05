// ThoughtMeter Connector — background service worker.
//
// Job: tell the local ThoughtMeter native host which hostname is active.
// Privacy rules enforced here:
//   - Only the hostname of the active tab is ever computed (hostnameFromUrl
//     discards the rest of the URL immediately).
//   - Nothing is sent anywhere except the local native messaging host.
//   - No page content, no content scripts, no history, no storage of URLs.
import { hostnameFromUrl } from "./lib.js";

const NATIVE_HOST = "org.thoughtmeter.chromehost";
const KEEPALIVE_ALARM = "thoughtmeter-keepalive";

let port = null;
// True only after the host actually answered on the current port. A freshly
// created port proves nothing: chrome.runtime.connectNative returns a port
// even when the host is missing — the failure arrives asynchronously via
// onDisconnect. Claiming "connected" at connect time made the popup report
// a working chain that did not exist.
let connected = false;
let lastHost = null; // hostname (or null) we last sent
let lastAck = null;  // last stateAck from the host: {tracked, trackedDomain}
let statusWaiters = []; // getStatus resolvers awaiting proof either way

function settleStatus() {
  const waiters = statusWaiters;
  statusWaiters = [];
  for (const resolve of waiters) resolve();
}

function connect() {
  if (port) return port;
  try {
    port = chrome.runtime.connectNative(NATIVE_HOST);
  } catch {
    connected = false;
    port = null;
    settleStatus();
    return null;
  }
  port.onMessage.addListener((message) => {
    if (message && message.type === "stateAck") {
      connected = true;
      lastAck = { tracked: !!message.tracked, trackedDomain: message.trackedDomain ?? null };
      settleStatus();
    }
  });
  port.onDisconnect.addListener(() => {
    connected = false;
    lastAck = null;
    port = null;
    settleStatus();
  });
  return port;
}

function send(message) {
  const activePort = connect();
  if (!activePort) return;
  try {
    activePort.postMessage(message);
  } catch {
    connected = false;
    port = null;
    settleStatus();
  }
}

/** Determine the active tab's hostname and push it to the host. */
async function refreshState() {
  let host = null;
  try {
    const window = await chrome.windows.getLastFocused();
    if (window && window.focused) {
      const [tab] = await chrome.tabs.query({ active: true, windowId: window.id });
      host = hostnameFromUrl(tab && tab.url);
    }
  } catch {
    host = null;
  }
  lastHost = host;
  send({ type: "state", host });
}

chrome.tabs.onActivated.addListener(() => { refreshState(); });

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  // Only the active tab's navigations matter, and only URL changes.
  if (tab && tab.active && changeInfo.url) refreshState();
});

chrome.windows.onFocusChanged.addListener(() => { refreshState(); });

// Keepalive: the macOS app treats state older than ~3 minutes as stale
// (fail closed), so re-send once a minute even when nothing changed.
chrome.alarms.create(KEEPALIVE_ALARM, { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === KEEPALIVE_ALARM) refreshState();
});

chrome.runtime.onStartup.addListener(() => { refreshState(); });
chrome.runtime.onInstalled.addListener(() => { refreshState(); });

// How long getStatus waits for the host to prove itself (ack) or fail
// (disconnect) before answering with the last known state. Local IPC
// settles in milliseconds; the timeout only guards a wedged host.
const STATUS_PROOF_TIMEOUT_MS = 700;

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message && message.type === "getStatus") {
    // The popup's query may be what woke a suspended worker, resetting the
    // module state above. Refresh, then wait for the host's ack — or the
    // onDisconnect that reveals a missing host — before answering.
    // Answering right after the refresh would race Chrome's asynchronous
    // failure delivery and always report "Connected".
    const proof = new Promise((resolve) => {
      statusWaiters.push(resolve);
      setTimeout(resolve, STATUS_PROOF_TIMEOUT_MS);
    });
    refreshState().then(() => proof).then(() => {
      sendResponse({
        connected,
        host: lastHost,
        tracked: lastAck ? lastAck.tracked : null,
        trackedDomain: lastAck ? lastAck.trackedDomain : null,
      });
    });
    return true; // keep the sendResponse channel open across the async work
  }
  return false;
});

refreshState();
