import Foundation

/// Turns (frontmost app, Chrome domain state, enabled sources) into the
/// source ID keystrokes should count toward — or nil for "don't count".
///
/// Recomputed only on events (app activation, Chrome state change, config
/// change), never per keystroke. The result is pushed into InputTracker.
public final class SourceResolver {
    private var appSourceIDs: [String: Int64] = [:]     // bundleID → source id
    private var domainSourceIDs: [String: Int64] = [:]  // domain → source id
    private let now: () -> Int64

    public init(clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }) {
        self.now = clock
    }

    /// Rebuild lookup tables from the currently *enabled* sources.
    public func updateEnabledSources(_ sources: [SourceRecord]) {
        var apps: [String: Int64] = [:]
        var domains: [String: Int64] = [:]
        for source in sources where source.isEnabled {
            switch source.kind {
            case .app:
                // Chrome must never act as a generic app source, even if a
                // row slipped into the database somehow.
                guard !RecognizedCatalog.isChrome(bundleID: source.identifier) else { continue }
                apps[source.identifier] = source.id
            case .domain:
                domains[source.identifier] = source.id
            }
        }
        appSourceIDs = apps
        domainSourceIDs = domains
    }

    /// Resolve the active source.
    /// - Chrome frontmost: count only with a fresh, tracked, still-enabled domain.
    /// - Any other app: count only if it is an enabled app source.
    public func resolve(frontmostBundleID: String?, chromeState: ChromeDomainState?) -> Int64? {
        guard let bundleID = frontmostBundleID else { return nil }
        if RecognizedCatalog.isChrome(bundleID: bundleID) {
            guard
                let state = chromeState,
                state.isFresh(now: now()),
                let domain = state.trackedDomain,
                let id = domainSourceIDs[domain]
            else { return nil }
            return id
        }
        return appSourceIDs[bundleID]
    }

    /// Enabled domains, for writing the native-host config file.
    public func enabledDomains() -> [String] {
        domainSourceIDs.keys.sorted()
    }
}
