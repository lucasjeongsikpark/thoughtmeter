import AppKit
import SwiftUI

/// Opens the app's Settings scene from contexts outside the MenuBarExtra
/// environment (e.g. the dashboard's NSWindow).
///
/// SwiftUI's `openSettings` environment action is the only reliable way to
/// open a Settings scene on modern macOS (the legacy `showSettingsWindow:`
/// responder action no longer reaches SwiftUI settings). Views that live
/// inside the scene (menu bar label, popover) register the action here so
/// plain NSWindows can reuse it.
@MainActor
enum SettingsOpener {
    private static var registeredAction: (() -> Void)?

    static func register(_ action: @escaping () -> Void) {
        registeredAction = action
    }

    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let registeredAction {
            registeredAction()
        } else {
            // Last-resort fallback if no scene view has appeared yet.
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

/// Opens the dashboard and onboarding as plain NSWindows.
///
/// ThoughtMeter is an LSUIElement (agent) app: SwiftUI WindowGroup scenes are
/// awkward to open programmatically from an AppDelegate, so windows are
/// managed directly. One instance per window id; reopening focuses it.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var windows: [String: NSWindow] = [:]

    func showDashboard() {
        show(
            id: "dashboard",
            title: "ThoughtMeter",
            size: NSSize(width: 780, height: 640),
            resizable: true,
            content: DashboardView().environmentObject(AppCoordinator.shared)
        )
    }

    func showOnboarding() {
        show(
            id: "onboarding",
            title: "Welcome to ThoughtMeter",
            size: NSSize(width: 620, height: 560),
            resizable: false,
            content: OnboardingView().environmentObject(AppCoordinator.shared)
        )
    }

    func closeOnboarding() {
        windows["onboarding"]?.close()
    }

    private func show<Content: View>(id: String, title: String, size: NSSize,
                                     resizable: Bool, content: Content) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.center()
        windows[id] = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.windows.removeValue(forKey: id) }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
