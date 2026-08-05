import SwiftUI
import ThoughtMeterKit

/// ThoughtMeter — a menu bar app (LSUIElement). The menu bar item is the only
/// permanent UI; the dashboard and onboarding open as regular windows.
@main
struct ThoughtMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var coordinator = AppCoordinator.shared

    init() {
        // Dev-only: `--render-previews <dir>` renders UI to PNGs and exits.
        PreviewRenderer.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(coordinator)
        } label: {
            MenuBarLabel(
                iconState: coordinator.menuBarIconState,
                text: coordinator.menuBarText
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
        }
    }
}

/// Menu bar item content: state-aware template icon plus optional count.
/// Also registers the scene's `openSettings` action with SettingsOpener —
/// the label exists for the whole app lifetime, so plain NSWindows (the
/// dashboard) can open Settings through it.
struct MenuBarLabel: View {
    @Environment(\.openSettings) private var openSettings
    let iconState: MenuBarIconState
    let text: String?

    var body: some View {
        Group {
            // NSImage is cached per state inside MenuBarIconRenderer.
            if let text {
                HStack(spacing: 3) {
                    Image(nsImage: MenuBarIconRenderer.image(for: iconState))
                    Text(text).font(.system(size: 12, weight: .medium).monospacedDigit())
                }
            } else {
                Image(nsImage: MenuBarIconRenderer.image(for: iconState))
            }
        }
        .onAppear {
            SettingsOpener.register { openSettings() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCoordinator.shared.start()
        if !AppCoordinator.shared.settings.onboardingComplete {
            WindowManager.shared.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCoordinator.shared.shutdown()
    }
}
