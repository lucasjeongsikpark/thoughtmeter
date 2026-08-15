import Foundation

/// Canonical on-disk locations. Everything lives under Application Support
/// so user data survives replacing the .app bundle during updates.
///
/// `THOUGHTMETER_DATA_DIR` overrides the base directory — used by tests and
/// by the native host in development. It must point at a user-writable path.
public enum DataPaths {
    public static var baseDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["THOUGHTMETER_DATA_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ThoughtMeter", isDirectory: true)
    }

    public static var databaseURL: URL {
        baseDirectory.appendingPathComponent("ThoughtMeter.sqlite")
    }

    public static var chromeDirectory: URL {
        baseDirectory.appendingPathComponent("chrome", isDirectory: true)
    }

    /// App → native host: selected domains.
    public static var chromeConfigURL: URL {
        chromeDirectory.appendingPathComponent("config.json")
    }

    /// Native host → app: current tracked domain (or null).
    public static var chromeStateURL: URL {
        chromeDirectory.appendingPathComponent("state.json")
    }

    /// Chrome's per-user native messaging host manifest location (stable Chrome).
    public static var chromeNativeMessagingManifestURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Google/Chrome/NativeMessagingHosts", isDirectory: true)
            .appendingPathComponent("\(NativeHostManifest.hostName).json")
    }

    /// Create the base + chrome directories with owner-only permissions,
    /// repairing the mode of any that already exist.
    ///
    /// `createDirectory`'s attributes apply only to directories it actually
    /// creates — with `withIntermediateDirectories: true` an existing directory
    /// is a silent no-op. Without the explicit repair, a directory created by
    /// an older build, restored from a backup, or loosened by hand would keep
    /// its permissions indefinitely while PRIVACY.md promised owner-only.
    public static func ensureDirectories() throws {
        let manager = FileManager.default
        for url in [baseDirectory, chromeDirectory] {
            try manager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }
}

/// Atomic, owner-only file writes shared by the app and the native host.
/// Write to a temp file in the same directory, then rename — readers never
/// observe a partial file.
public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: temporary, options: [])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        // rename(2) is atomic within a filesystem; replaceItem handles the
        // "destination exists" case portably.
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    public static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try write(try encoder.encode(value), to: url)
    }

    public static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
