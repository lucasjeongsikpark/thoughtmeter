import Foundation
import ThoughtMeterKit

/// Release-time configuration. The production Chrome extension ID is injected
/// into Info.plist by the packaging scripts (single source:
/// packaging/release-config.sh). A development extension ID can be set in
/// Settings ▸ Chrome for unpacked-extension testing.
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
        case noExtensionID

        var description: String {
            switch self {
            case .hostBinaryMissing:
                return "The native host binary was not found next to the app executable."
            case .noExtensionID:
                return "No Chrome extension ID is configured. Set a development ID in Settings ▸ Chrome, or install a release build."
            }
        }
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

    static func allowedOrigins() -> [String] {
        var ids: [String] = []
        if let production = ReleaseConfig.productionExtensionID { ids.append(production) }
        // One malformed origin invalidates the ENTIRE manifest in Chrome,
        // which would sever the store extension's connection too — never let
        // a bad saved dev ID through. (Settings validates on entry; this
        // covers a value persisted before that check existed.)
        if let development = ReleaseConfig.developmentExtensionID,
           ChromeExtensionID.isPlausible(development) {
            ids.append(development)
        }
        return ids.map { "chrome-extension://\($0)/" }
    }

    static func install() throws {
        guard let hostBinary = hostBinaryURL else { throw InstallError.hostBinaryMissing }
        let origins = allowedOrigins()
        guard !origins.isEmpty else { throw InstallError.noExtensionID }

        let manifest: [String: Any] = [
            "name": "org.thoughtmeter.chromehost",
            "description": "ThoughtMeter native messaging host (local only)",
            "path": hostBinary.path,
            "type": "stdio",
            "allowed_origins": origins,
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try AtomicFile.write(data, to: manifestURL)
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
        guard path.hasSuffix("NativeMessagingHosts/org.thoughtmeter.chromehost.json") else { return }
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }
}
