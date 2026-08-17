import Foundation
import ThoughtMeterKit

/// Release-time configuration. The production Chrome extension ID is injected
/// into Info.plist by the packaging scripts (single source:
/// packaging/release-config.sh). Contributors testing a locally loaded
/// extension set a development ID with
/// `defaults write org.thoughtmeter.app devChromeExtensionID <ID>`
/// (documented in CONTRIBUTING.md).
enum ReleaseConfig {
    static var productionExtensionID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TMChromeExtensionID") as? String,
              !value.isEmpty, value != "UNSET" else { return nil }
        return value
    }

    static var developmentExtensionID: String? {
        get {
            let value = UserDefaults.standard.string(forKey: "devChromeExtensionID") ?? ""
            return value.isEmpty ? nil : value
        }
        set {
            UserDefaults.standard.set(newValue ?? "", forKey: "devChromeExtensionID")
        }
    }

    /// The released Chrome Web Store listing for ThoughtMeter Connector.
    /// Shown (and opened in the user's browser) by Settings ▸ Chrome — the
    /// app itself never fetches it.
    static let chromeWebStoreURLString =
        "https://chromewebstore.google.com/detail/thoughtmeter-connector/omhnbpfiapchifodmobgeglhgpgolmhn"

    static var repositoryURLString: String {
        (Bundle.main.object(forInfoDictionaryKey: "TMRepositoryURL") as? String)
            ?? "github.com/lucasjeongsikpark/thoughtmeter"
    }

    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }
}

/// Writes / removes the Chrome Native Messaging host manifest that lets the
/// extension talk to the bundled thoughtmeter-native-host binary.
enum NativeHostInstaller {
    enum InstallError: Error, CustomStringConvertible {
        case hostBinaryMissing
        case appNotInstalled

        var description: String {
            switch self {
            case .hostBinaryMissing:
                return "The native host binary was not found next to the app executable."
            case .appNotInstalled:
                return "Move ThoughtMeter to your Applications folder before enabling the Chrome Connector. Chrome needs a permanent path to the app, and this copy is running from a disk image or a read-only location that disappears when it is ejected."
            }
        }
    }

    /// True when the running bundle sits somewhere the path will not survive:
    /// a mounted disk image, or macOS's App Translocation sandbox (which is
    /// where a downloaded app runs until the user moves it).
    ///
    /// Deliberately NOT a plain `/Volumes/` prefix check: an external drive is
    /// also mounted under /Volumes, and installing to one is a legitimate
    /// choice on a Mac with a small internal disk. Read-only is the property
    /// that actually predicts a dead manifest path.
    static var isRunningFromTemporaryLocation: Bool {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        if bundleURL.path.contains("/AppTranslocation/") { return true }
        if let values = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]),
           values.volumeIsReadOnly == true {
            return true
        }
        return false
    }

    /// The host binary ships inside the app bundle (Contents/MacOS/).
    /// In development (`swift run` / `swift build`), it sits in the same
    /// build directory as the app executable, so this works unchanged.
    static var hostBinaryURL: URL? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let candidate = executable.deletingLastPathComponent()
            .appendingPathComponent("thoughtmeter-native-host")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    static var manifestURL: URL { DataPaths.chromeNativeMessagingManifestURL }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    /// Validation and ordering live in the Kit so `make test` can reach them
    /// (the test runner does not depend on the app target).
    static func allowedOrigins() throws -> [String] {
        try NativeHostManifest.origins(
            production: ReleaseConfig.productionExtensionID,
            development: ReleaseConfig.developmentExtensionID
        )
    }

    static func install() throws {
        guard !isRunningFromTemporaryLocation else { throw InstallError.appNotInstalled }
        guard let hostBinary = hostBinaryURL else { throw InstallError.hostBinaryMissing }
        let origins = try allowedOrigins()

        let manifest: [String: Any] = [
            "name": NativeHostManifest.hostName,
            "description": "ThoughtMeter native messaging host (local only)",
            "path": hostBinary.path,
            "type": "stdio",
            "allowed_origins": origins,
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try AtomicFile.write(data, to: manifestURL)
    }

    /// Re-register the manifest when the one on disk no longer describes this
    /// app — the case that matters is the user moving or renaming
    /// ThoughtMeter.app, which leaves Chrome pointing at a path that no longer
    /// exists and shows up only as a permanent "Not connected".
    ///
    /// Repairs, never escalates: it runs only when a manifest already exists
    /// (so Chrome was set up deliberately) and writes exactly the origins this
    /// build would compute anyway.
    static func ensureInstalledIfNeeded() {
        guard isInstalled else { return }
        guard !isRunningFromTemporaryLocation else { return }
        guard let hostBinary = hostBinaryURL else { return }

        let expectedOrigins: [String]
        do {
            expectedOrigins = try allowedOrigins()
        } catch {
            NSLog("ThoughtMeter: connector manifest not repaired — \(error)")
            return
        }

        let state: NativeHostManifest.InstalledState
        if let data = try? Data(contentsOf: manifestURL) {
            state = NativeHostManifest.decodeInstalled(data)
        } else {
            state = .unreadable
        }

        var installedPathExists = false
        if case .present(let installed) = state {
            installedPathExists = FileManager.default.isExecutableFile(atPath: installed.path)
        }

        guard NativeHostManifest.repairIsNeeded(
            state,
            expectedPath: hostBinary.path,
            expectedOrigins: expectedOrigins,
            installedPathExists: installedPathExists
        ) else { return }

        do {
            try install()
            NSLog("ThoughtMeter: connector manifest repaired (now pointing at \(hostBinary.path))")
        } catch {
            NSLog("ThoughtMeter: connector manifest repair failed — \(error)")
        }
    }

    /// Origins listed in the currently installed manifest (for status UI).
    static func installedOrigins() -> [String] {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let origins = manifest["allowed_origins"] as? [String]
        else { return [] }
        return origins
    }

    static func uninstall() throws {
        let path = manifestURL.path
        // Path safety: only ever delete our own manifest file.
        guard path.hasSuffix("NativeMessagingHosts/\(NativeHostManifest.hostName).json") else { return }
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }
}
