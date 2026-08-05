// Pure functions, unit-tested with `node --test`.
// Mirrors DomainNormalizer.swift — keep the two in sync.

/**
 * Normalize a hostname: lowercase, strip trailing dot and leading "www.",
 * validate ASCII hostname labels, require at least two labels.
 * Returns null for anything that is not a plausible tracked domain.
 * @param {string} raw
 * @returns {string | null}
 */
export function normalizeHostname(raw) {
  if (typeof raw !== "string") return null;
  let host = raw.trim().toLowerCase();
  if (host.endsWith(".")) host = host.slice(0, -1);
  if (host.startsWith("www.")) host = host.slice(4);
  if (host.length === 0 || host.length > 253) return null;

  const labels = host.split(".");
  if (labels.length < 2) return null;
  for (const label of labels) {
    if (label.length === 0 || label.length > 63) return null;
    if (!/^[a-z0-9-]+$/.test(label)) return null;
    if (label.startsWith("-") || label.endsWith("-")) return null;
  }
  return host;
}

/**
 * Reduce a full URL to a normalized hostname — the full URL never leaves
 * this function. Only http(s) pages can be tracked domains.
 * @param {string | undefined} urlString
 * @returns {string | null}
 */
export function hostnameFromUrl(urlString) {
  if (!urlString) return null;
  try {
    const url = new URL(urlString);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    return normalizeHostname(url.hostname);
  } catch {
    return null;
  }
}
