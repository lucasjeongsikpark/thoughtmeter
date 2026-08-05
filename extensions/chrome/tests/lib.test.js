import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeHostname, hostnameFromUrl } from "../src/lib.js";

test("normalizes simple hostnames", () => {
  assert.equal(normalizeHostname("claude.ai"), "claude.ai");
  assert.equal(normalizeHostname("ChatGPT.com"), "chatgpt.com");
  assert.equal(normalizeHostname("  claude.ai  "), "claude.ai");
});

test("strips www prefix and trailing dot", () => {
  assert.equal(normalizeHostname("www.example.com"), "example.com");
  assert.equal(normalizeHostname("claude.ai."), "claude.ai");
});

test("rejects invalid hostnames", () => {
  assert.equal(normalizeHostname(""), null);
  assert.equal(normalizeHostname("localhost"), null);
  assert.equal(normalizeHostname("has space.com"), null);
  assert.equal(normalizeHostname("bad..com"), null);
  assert.equal(normalizeHostname("-bad.com"), null);
  assert.equal(normalizeHostname("bad-.com"), null);
  assert.equal(normalizeHostname("a".repeat(300) + ".com"), null);
  assert.equal(normalizeHostname(undefined), null);
});

test("full URL is reduced to hostname only", () => {
  assert.equal(hostnameFromUrl("https://claude.ai/chat/secret-conversation?q=1#x"), "claude.ai");
  assert.equal(hostnameFromUrl("https://www.chatgpt.com/some/path"), "chatgpt.com");
  assert.equal(hostnameFromUrl("http://chat.claude.ai:8080/x"), "chat.claude.ai");
});

test("non-web schemes are never trackable", () => {
  assert.equal(hostnameFromUrl("chrome://extensions"), null);
  assert.equal(hostnameFromUrl("file:///Users/me/doc.html"), null);
  assert.equal(hostnameFromUrl("about:blank"), null);
  assert.equal(hostnameFromUrl("chrome-extension://abc/popup.html"), null);
});

test("missing or malformed URLs yield null", () => {
  assert.equal(hostnameFromUrl(undefined), null);
  assert.equal(hostnameFromUrl(""), null);
  assert.equal(hostnameFromUrl("not a url"), null);
});
