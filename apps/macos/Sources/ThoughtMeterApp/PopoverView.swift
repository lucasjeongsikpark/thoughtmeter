import SwiftUI
import ThoughtMeterKit

/// Compact menu bar popover: today's total, top three sources, status, actions.
/// The full analytics live in the dashboard window.
struct PopoverView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today’s Thought Input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(CountFormatter.exact(coordinator.todayTotal))
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    Text("keystrokes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !topThree.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(topThree, id: \.source.id) { entry in
                        HStack(spacing: 7) {
                            SourceIcon(source: entry.source, size: 15)
                            Text(entry.source.displayName)
                                .lineLimit(1)
                            Spacer()
                            Text(CountFormatter.exact(entry.keystrokes))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            } else {
                Text("Start typing in a selected tool to see your Thought Input here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                statusRow
                if !coordinator.trackingHealthy {
                    Button("Open Input Monitoring Settings") {
                        coordinator.permission.request()
                        PermissionMonitor.openSystemSettings()
                    }
                    .controlSize(.small)
                    Text("If ThoughtMeter is already listed, toggle it off and on (updates can invalidate the grant), then return here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let current = coordinator.currentSourceName {
                    HStack(spacing: 5) {
                        Text("Current:").foregroundStyle(.secondary)
                        Text(current)
                    }
                    .font(.caption)
                }
            }

            HStack(spacing: 8) {
                Button("Open Dashboard") {
                    WindowManager.shared.showDashboard()
                }
                .controlSize(.small)

                pauseMenu

                Button("Settings") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear {
            coordinator.popoverVisible = true
            coordinator.refreshNow()
            SettingsOpener.register { openSettings() }
        }
        .onDisappear { coordinator.popoverVisible = false }
    }

    private var topThree: [(source: SourceRecord, keystrokes: Int)] {
        Array(coordinator.todayBySource.prefix(3))
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 5) {
            Text("Tracking:").foregroundStyle(.secondary)
            if !coordinator.permissionGranted {
                Text("Input Monitoring needed").foregroundStyle(.orange)
            } else if !coordinator.tapRunning {
                Text("Input Monitoring lost — re-grant needed").foregroundStyle(.orange)
            } else if coordinator.isPaused {
                Text(coordinator.pauseDescription).foregroundStyle(.orange)
            } else if coordinator.chromeRelevant && !coordinator.chromeConnected {
                Text("Active — Chrome extension not connected").foregroundStyle(.orange)
            } else {
                Text("Active")
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var pauseMenu: some View {
        if coordinator.isPaused {
            Button("Resume") { coordinator.resumeTracking() }
                .controlSize(.small)
        } else {
            Menu("Pause") {
                Button("Pause for 15 minutes") { coordinator.pause(for: 15 * 60) }
                Button("Pause for 1 hour") { coordinator.pause(for: 60 * 60) }
                Button("Pause until tomorrow") { coordinator.pauseUntilTomorrow() }
                Button("Pause indefinitely") { coordinator.pause(for: nil) }
            }
            .controlSize(.small)
            .fixedSize()
        }
    }
}
