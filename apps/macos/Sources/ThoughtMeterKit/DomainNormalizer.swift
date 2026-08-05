import Foundation

/// Hostname normalization and matching.
///
/// Used in three places with the same rules:
/// - the Chrome extension (JavaScript twin in extensions/chrome/src/lib.js)
/// - the native messaging host (defensive re-normalization)
/// - the macOS app (validating user-entered custom domains)
public enum DomainNormalizer {
    /// Normalize user- or browser-supplied input to a bare lowercase hostname.
    ///
    /// Forgiving on input (strips scheme, path, port, leading `www.`),
    /// strict on output (ASCII hostname labels only, at least one dot).
    /// Returns nil for anything that is not a plausible public hostname.
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Strip scheme ("https://claude.ai/chat" is accepted as user input).
        if let schemeRange = s.range(of: "://") {
            s = String(s[schemeRange.upperBound...])
        }
        // Strip path / query / fragment.
        if let slash = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            s = String(s[..<slash])
        }
        // Reject user-info; strip port.
        if s.contains("@") { return nil }
        if let colon = s.firstIndex(of: ":") {
            let port = s[s.index(after: colon)...]
            guard !port.isEmpty, port.allSatisfy({ $0.isNumber }) else { return nil }
            s = String(s[..<colon])
        }
        if s.hasSuffix(".") { s.removeLast() }
        if s.hasPrefix("www.") { s.removeFirst(4) }

        guard !s.isEmpty, s.count <= 253 else { return nil }

        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        // Require at least two labels: bare single labels ("localhost") and
        // raw IPs with fewer dots are not meaningful tracked domains.
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return nil }
            guard label.first != "-", label.last != "-" else { return nil }
            for ch in label {
                let ok = (ch.isASCII && (ch.isLetter || ch.isNumber)) || ch == "-"
                guard ok else { return nil }
            }
        }
        return s
    }

    /// A selected domain matches itself and any subdomain.
    /// `claude.ai` matches `claude.ai` and `chat.claude.ai`, never `notclaude.ai`.
    public static func matches(host: String, selectedDomain: String) -> Bool {
        host == selectedDomain || host.hasSuffix("." + selectedDomain)
    }

    /// The canonical selected domain a hostname should be attributed to,
    /// or nil if the hostname matches no selected domain.
    /// The longest (most specific) selected domain wins.
    public static func canonicalSelectedDomain(forHost host: String, in selected: [String]) -> String? {
        selected
            .filter { matches(host: host, selectedDomain: $0) }
            .max { $0.count < $1.count }
    }
}
