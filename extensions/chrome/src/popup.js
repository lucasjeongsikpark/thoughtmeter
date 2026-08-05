// Popup: read-only status view. Configuration lives in the macOS app.
function dot(kind) {
  const span = document.createElement("span");
  span.className = `dot ${kind}`;
  return span;
}

function setStatus(id, text, kind) {
  const element = document.getElementById(id);
  element.textContent = "";
  if (kind) element.appendChild(dot(kind));
  element.appendChild(document.createTextNode(text));
}

chrome.runtime.sendMessage({ type: "getStatus" }, (status) => {
  if (chrome.runtime.lastError || !status) {
    setStatus("connection", "Extension starting…", "neutral");
    setStatus("host", "—");
    setStatus("tracked", "—");
    return;
  }
  setStatus("connection", status.connected ? "Connected" : "Not connected", status.connected ? "ok" : "off");
  setStatus("host", status.host || "No trackable site");
  if (status.tracked === null) {
    setStatus("tracked", "—");
  } else if (status.tracked) {
    setStatus("tracked", `Yes (${status.trackedDomain})`, "ok");
  } else {
    setStatus("tracked", "No", "neutral");
  }
});
