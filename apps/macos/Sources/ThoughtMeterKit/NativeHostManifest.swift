import Foundation

/// The Chrome Native Messaging host manifest ThoughtMeter registers so the
/// Connector extension can reach the bundled host binary.
///
/// The decisions live here, in the Kit, rather than in the app target that
/// performs the write: the test runner does not depend on the app target, so
/// anything defined there is unreachable from `make test`.
public enum NativeHostManifest {
    /// Must match the extension's `connectNative()` argument and
    /// `NATIVE_HOST_NAME` in packaging/release-config.sh.
    public static let hostName = "org.thoughtmeter.chromehost"

    public enum OriginError: Error, Equatable, CustomStringConvertible {
        case invalidProductionExtensionID(String)
        case noExtensionID

        public var description: String {
            switch self {
            case .invalidProductionExtensionID(let id):
                return """
                    This build carries an invalid Chrome Web Store extension ID (\"\(id)\"). \
                    Chrome would reject the whole connector manifest, so nothing was registered.
                    """
            case .noExtensionID:
                return "No Chrome extension ID is configured. Set a development ID in Settings ▸ Chrome, or install a release build."
            }
        }
    }

    /// The manifest's `allowed_origins`.
    ///
    /// Chrome treats `allowed_origins` as all-or-nothing: one malformed entry
    /// invalidates the ENTIRE manifest, severing the Web Store extension's
    /// connection too. Hence both IDs are checked — but they fail differently:
    ///
    /// - An invalid **production** ID throws. It comes from release
    ///   configuration, so dropping it silently would hide a release mistake
    ///   behind a runtime symptom ("Not connected") instead of naming it.
    /// - An invalid **development** ID is filtered out. It is user-entered and
    ///   may predate the Settings-entry check, so dropping it self-heals an
    ///   install that would otherwise be wedged (D42).
    public static func origins(production: String?, development: String?) throws -> [String] {
        var ids: [String] = []

        if let production, !production.isEmpty, production != "UNSET" {
            guard ChromeExtensionID.isPlausible(production) else {
                throw OriginError.invalidProductionExtensionID(production)
            }
            ids.append(production)
        }

        if let development, ChromeExtensionID.isPlausible(development) {
            ids.append(development)
        }

        // Production first, then development, each at most once: the order is
        // a function of the inputs alone, so a manifest can be compared against
        // freshly computed origins to decide whether it needs repair.
        var seen = Set<String>()
        let origins = ids
            .filter { seen.insert($0).inserted }
            .map { "chrome-extension://\($0)/" }

        guard !origins.isEmpty else { throw OriginError.noExtensionID }
        return origins
    }

    // MARK: - Repair

    /// The parts of an installed manifest that can go stale.
    public struct Installed: Equatable {
        public let path: String
        public let origins: [String]

        public init(path: String, origins: [String]) {
            self.path = path
            self.origins = origins
        }
    }

    public enum InstalledState: Equatable {
        case absent
        /// The file exists but is not a manifest we can read (truncated write,
        /// hand-edited JSON, a older/newer shape).
        case unreadable
        case present(Installed)
    }

    public static func decodeInstalled(_ data: Data) -> InstalledState {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["path"] as? String,
              let origins = object["allowed_origins"] as? [String]
        else { return .unreadable }
        return .present(Installed(path: path, origins: origins))
    }

    /// Whether an already-registered manifest has drifted from what this build
    /// would write now.
    ///
    /// The manifest hard-codes an absolute path to the host binary (Chrome
    /// requires that on macOS), so moving or renaming ThoughtMeter.app silently
    /// severs the connector until the user re-registers it by hand.
    ///
    /// Two rules keep this a repair rather than a takeover:
    ///
    /// - `absent` means no repair. A user who never set up Chrome has not asked
    ///   for a manifest, and writing one at startup would register a native
    ///   messaging host behind their back.
    /// - A path pointing at a host binary that still EXISTS is left alone, even
    ///   when it is not this copy's. Otherwise a debug build launched from
    ///   `.build/dev` would repoint Chrome at itself and away from the copy in
    ///   /Applications, and the two would trade the registration back and forth
    ///   on every launch. Only a dead path is worth taking over — that is the
    ///   actual failure being fixed.
    ///
    /// `installedPathExists` is passed in rather than probed here so the
    /// decision stays a pure function.
    public static func repairIsNeeded(
        _ state: InstalledState,
        expectedPath: String,
        expectedOrigins: [String],
        installedPathExists: Bool
    ) -> Bool {
        switch state {
        case .absent:
            return false
        case .unreadable:
            return true
        case .present(let installed):
            if installed.origins != expectedOrigins { return true }
            if installed.path == expectedPath { return false }
            return !installedPathExists
        }
    }
}
