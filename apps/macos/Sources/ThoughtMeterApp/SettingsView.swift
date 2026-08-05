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
    @State private var devExtensionID = ReleaseConfig.developmentExtensionID ?? ""
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Extension", value: coordinator.chromeStateDescription)
                LabeledContent("Connector manifest", value: NativeHostInstaller.isInstalled ? "Registered" : "Not registered")
                if NativeHostInstaller.isInstalled {
                    let origins = NativeHostInstaller.installedOrigins()
                    LabeledContent("Allowed extension IDs",
                                   value: origins.isEmpty ? "none" : origins.map(shortOrigin).joined(separator: ", "))
                }
                Button("Refresh Status") { coordinator.refreshNow() }
            }

            Section("Set up") {
                VStack(alignment: .leading, spacing: 8) {
                    setupStep(1, "In Chrome, open a new tab and go to  chrome://extensions , then turn on “Developer mode” (top right).")
                    setupStep(2, "Click “Load unpacked” and choose the  extensions/chrome  folder inside the ThoughtMeter repository.")
                    setupStep(3, "Copy the ID shown on the ThoughtMeter Connector card, paste it below, and click “Save ID & Register”.")
                    setupStep(4, "Quit Chrome completely (⌘Q) and reopen it — Chrome reads the connector registration at launch.")
                }
                .padding(.vertical, 2)
                HStack {
                    TextField("Extension ID from chrome://extensions", text: $devExtensionID)
                        .onSubmit { saveDevID() }
                    Button("Save ID & Register") { saveDevID() }
                        .disabled(devExtensionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  && ReleaseConfig.productionExtensionID == nil)
                }
                Text("Once ThoughtMeter Connector is on the Chrome Web Store, installing it from there needs no ID — release builds know the store extension automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Still “not connected”? In order: 1) confirm the connector manifest is registered above, 2) confirm the extension ID above matches chrome://extensions exactly, 3) reload the extension, 4) quit and reopen Chrome. If you moved or rebuilt ThoughtMeter.app, register again — the manifest points at the app's location on disk.")
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

    private func shortOrigin(_ origin: String) -> String {
        origin
            .replacingOccurrences(of: "chrome-extension://", with: "")
            .replacingOccurrences(of: "/", with: "")
    }

    private func runInstall() {
        do {
            try NativeHostInstaller.install()
            statusMessage = "Connector registered. Next: reload the extension at chrome://extensions, then quit and reopen Chrome (⌘Q)."
        } catch {
            statusMessage = String(describing: error)
        }
    }

    private func saveDevID() {
        // Newlines matter here: text pasted from chrome://extensions often
        // carries a trailing one, and Chrome rejects the whole manifest over
        // a single malformed allowed_origins entry.
        let trimmed = devExtensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !ChromeExtensionID.isPlausible(trimmed) {
            statusMessage = "That doesn't look like a Chrome extension ID — expected 32 letters (a–p), as shown on the ThoughtMeter Connector card at chrome://extensions. Nothing was changed."
            return
        }
        ReleaseConfig.developmentExtensionID = trimmed.isEmpty ? nil : trimmed
        runInstall()
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
