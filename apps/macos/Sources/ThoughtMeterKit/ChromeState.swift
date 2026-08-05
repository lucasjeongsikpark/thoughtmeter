import Foundation

/// State written by the native messaging host and read by the app.
///
/// Privacy invariant: `trackedDomain` is either one of the user's selected
/// domains (canonical form) or nil. Hostnames of non-selected sites never
/// reach this file — the host reduces them to nil before writing.
public struct ChromeDomainState: Codable, Equatable {
    public let trackedDomain: String?
    /// Unix seconds when the host last heard from the extension.
    public let updatedAt: Int64

    public init(trackedDomain: String?, updatedAt: Int64) {
        self.trackedDomain = trackedDomain
        self.updatedAt = updatedAt
    }

    /// Chrome state is trusted only within a bounded window (the extension
    /// re-sends state every minute). Stale or future-dated state means the
    /// host may be dead — fail closed and count nothing for Chrome.
    public static let freshnessWindowSeconds: Int64 = 180

    public func isFresh(now: Int64) -> Bool {
        let age = now - updatedAt
        return age >= -60 && age <= Self.freshnessWindowSeconds
    }
}

/// Selected-domain configuration written by the app for the native host.
public struct ChromeHostConfig: Codable, Equatable {
    /// Enabled domain sources, normalized (e.g. ["chatgpt.com", "claude.ai"]).
    public var domains: [String]
    public var updatedAt: Int64

    public init(domains: [String], updatedAt: Int64) {
        self.domains = domains
        self.updatedAt = updatedAt
    }
}
