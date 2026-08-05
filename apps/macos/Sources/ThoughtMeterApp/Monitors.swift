import AppKit
import CoreGraphics
import ThoughtMeterKit

/// Caches the frontmost application's bundle identifier.
/// Event-driven (NSWorkspace activation notifications) — never polls.
final class FrontmostAppMonitor {
    private(set) var currentBundleID: String?
    var onChange: ((String?) -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.currentBundleID = app?.bundleIdentifier
            self.onChange?(self.currentBundleID)
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}

/// Input Monitoring permission state.
///
/// There is no notification for permission changes, so while (and only while)
/// the permission is missing, this polls every 3 seconds. Once granted, the
/// timer stops and never restarts unless the tap reports failure again.
final class PermissionMonitor: ObservableObject {
    @Published private(set) var granted: Bool = CGPreflightListenEventAccess()
    var onGranted: (() -> Void)?
    private var timer: Timer?

    /// Ask macOS to register the app in the Input Monitoring list and prompt.
    func request() {
        CGRequestListenEventAccess()
        recheck()
        startPollingIfNeeded()
    }

    func recheck() {
        let now = CGPreflightListenEventAccess()
        if now != granted {
            granted = now
            if now {
                stopPolling()
                onGranted?()
            }
        }
    }

    func startPollingIfNeeded() {
        guard !granted, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.recheck()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}

/// Detects installed applications and resolves picked .app bundles.
enum InstalledApps {
    struct Detected: Identifiable, Equatable {
        var id: String { bundleID }
        let bundleID: String
        let displayName: String
        let appURL: URL

        static func == (lhs: Detected, rhs: Detected) -> Bool { lhs.bundleID == rhs.bundleID }
    }

    /// Recognized catalog entries that are actually installed on this Mac,
    /// verified against real .app bundles (never trusting the hard-coded ID alone).
    /// The curated catalog name is used ("Visual Studio Code", not "Code").
    static func detectedRecognizedApps() -> [Detected] {
        RecognizedCatalog.apps.compactMap { candidate in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID),
                  let bundle = Bundle(url: url),
                  let realID = bundle.bundleIdentifier,
                  realID == candidate.bundleID
            else { return nil }
            return Detected(bundleID: realID, displayName: candidate.displayName, appURL: url)
        }
    }

    /// Inspect an arbitrary .app the user picked.
    static func inspect(appAt url: URL) -> Detected? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        return Detected(bundleID: bundleID,
                        displayName: displayName(of: bundle, fallback: url.deletingPathExtension().lastPathComponent),
                        appURL: url)
    }

    static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func displayName(of bundle: Bundle, fallback: String) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallback
    }
}
