import AppKit
import SwiftUI
import ThoughtMeterKit

struct SettingsView: View {
    var body: some View {
        TabView {
            TrackingSettings()
                .tabItem { Label("Tracking", systemImage: "keyboard") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "menubar.rectangle") }
            DataSettings()
                .tabItem { Label("Data", systemImage: "internaldrive") }
            ChromeSettings()
                .tabItem { Label("Chrome", systemImage: "globe") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - Tracking

private struct TrackingSettings: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Tracking mode", selection: Binding(
                get: { coordinator.settings.trackingMode },
                set: { coordinator.setTrackingMode($0) }
            )) {
                ForEach(TrackingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            SourceChecklist()

            HStack {
                Text("Tracking status: \(coordinator.pauseDescription)")
                    .foregroundStyle(coordinator.isPaused ? .orange : .secondary)
                Spacer()
                if coordinator.isPaused {
                    Button("Resume") { coordinator.resumeTracking() }
                } else {
                    Button("Pause indefinitely") { coordinator.pause(for: nil) }
                }
            }
            .font(.callout)
        }
        .padding(20)
        .onAppear { coordinator.reloadSources() }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Picker("Menu bar shows", selection: Binding(
                get: { coordinator.settings.menuBarDisplay },
                set: { coordinator.setMenuBarDisplay($0) }
            )) {
                ForEach(MenuBarDisplay.allCases, id: \.self) { display in
                    Text(display.displayName).tag(display)
                }
            }
            .pickerStyle(.inline)

            Toggle("Launch ThoughtMeter at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    coordinator.setLaunchAtLogin(newValue)
                }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = coordinator.launchAtLoginEnabled }
    }
}

// MARK: - Data

private struct DataSettings: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var deleteConfirmationShown = false

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Location", value: DataPaths.baseDirectory.path)
                LabeledContent("Size on disk", value: coordinator.storageUsageDescription)
                Button("Reveal Data Folder in Finder") { coordinator.revealDataFolder() }
            }
            Section("Export") {
                Button("Export CSV…") { coordinator.exportCSV() }
                Text("The export contains minute-level aggregate counts per source — no key data, no URLs, no titles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Retention") {
                Text("ThoughtMeter keeps your Thought Input history until you delete it. Nothing expires automatically, and nothing ever leaves this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Delete All ThoughtMeter Data…", role: .destructive) {
                    deleteConfirmationShown = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete all recorded Thought Input?",
            isPresented: $deleteConfirmationShown,
            titleVisibility: .visible
        ) {
            Button("Delete All History", role: .destructive) { coordinator.deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every recorded count from this Mac. Your source selection and settings are kept. This cannot be undone.")
        }
    }
}

// MARK: - Chrome

private struct ChromeSettings: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Extension", value: coordinator.chromeStateDescription)
                LabeledContent("Connector manifest", value: NativeHostInstaller.isInstalled ? "Registered" : "Not registered")
                Button("Refresh Status") { coordinator.refreshNow() }
            }

            Section("Set up") {
                VStack(alignment: .leading, spacing: 8) {
                    setupStep(1, "Install “ThoughtMeter Connector” from the Chrome Web Store.")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ReleaseConfig.chromeWebStoreURLString)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Open") { openWebStoreListing() }
                            .controlSize(.small)
                    }
                    .padding(.leading, 18)
                    setupStep(2, "Click “Register Connector” below — the Web Store extension needs no ID.")
                    Button("Register Connector") { runInstall() }
                        .padding(.leading, 18)
                    setupStep(3, "Quit Chrome completely (⌘Q) and reopen it — Chrome reads the connector registration at launch.")
                }
                .padding(.vertical, 2)

                if ReleaseConfig.productionExtensionID == nil {
                    Text("This build carries no Chrome Web Store extension ID, so registering here cannot authorize the store extension — that path works in release builds. Contributors building from source: see CONTRIBUTING.md, “Developing the Chrome extension”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tracked domains") {
                let domains = coordinator.sources.filter { $0.kind == .domain && $0.isEnabled }
                if domains.isEmpty {
                    Text("No domains selected yet. Enable them in the Tracking tab — without the extension they simply don't count.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(domains) { source in
                        HStack(spacing: 8) {
                            SourceIcon(source: source, size: 16)
                            Text(source.identifier)
                        }
                    }
                }
            }

            Section("Troubleshooting") {
                Text("Still “not connected”? In order: 1) click “Register Connector” above — it writes a fresh manifest either way, 2) reload the extension at chrome://extensions, 3) quit and reopen Chrome. If you moved or rebuilt ThoughtMeter.app, click “Register Connector” again — the manifest points at the app's location on disk.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Hands the URL to the user's default browser. ThoughtMeter itself makes
    /// no network requests — the browser does the fetching.
    private func openWebStoreListing() {
        guard let url = URL(string: ReleaseConfig.chromeWebStoreURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func runInstall() {
        do {
            try NativeHostInstaller.install()
            statusMessage = "Connector registered. Next: reload the extension at chrome://extensions, then quit and reopen Chrome (⌘Q)."
        } catch {
            statusMessage = String(describing: error)
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("ThoughtMeter")
                .font(.title2.weight(.semibold))
            Text("Version \(ReleaseConfig.appVersion)")
                .foregroundStyle(.secondary)
            Text("Measure the human side of AI work.")
                .font(.callout)

            Divider().padding(.vertical, 4)

            VStack(spacing: 6) {
                Text("Open source under the MIT License.")
                Text(ReleaseConfig.repositoryURLString)
                    .textSelection(.enabled)
                    .font(.callout.monospaced())
                Text("ThoughtMeter performs no update checks and makes no network requests. New versions are announced only on the GitHub repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(24)
    }
}
