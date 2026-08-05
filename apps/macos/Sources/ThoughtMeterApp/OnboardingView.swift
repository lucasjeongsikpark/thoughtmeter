import AppKit
import SwiftUI
import ThoughtMeterKit

/// Six-step onboarding. Tracking begins only after the user explicitly
/// finishes step 4's source selection and completes the flow.
struct OnboardingView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var step = 0

    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: IdeaStep()
                case 1: PrivacyStep()
                case 2: PermissionStep()
                case 3: SourcesStep()
                case 4: LoginStep()
                default: ChromeStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)

            Divider()

            HStack {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                if step < totalSteps - 1 {
                    Button("Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Finish & Start Tracking") {
                        coordinator.finishOnboarding()
                        WindowManager.shared.closeOnboarding()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 620, height: 560)
    }
}

// MARK: - Steps

private struct IdeaStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Measure the human side of AI work.")
                .font(.largeTitle.weight(.semibold))
            Text("AI systems measure everything they generate — tokens, cost, latency, output. ThoughtMeter measures one visible trace of the human input behind them: the keystrokes you type inside the AI tools and workspaces you choose.")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Not every keystroke is a thought.\nBut thinking leaves traces.")
                .font(.title3.italic())
                .padding(.top, 8)
            Spacer()
            Text("ThoughtMeter counts keystrokes. It never claims to measure intelligence, effort, or productivity — it is an honest, local record of your participation.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PrivacyStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Private by design")
                .font(.title.weight(.semibold))
            Text("ThoughtMeter counts keyboard events. It does not record which keys you press.")
                .font(.title3)

            VStack(alignment: .leading, spacing: 8) {
                bullet("Only counts are stored — never keys, characters, or text.")
                bullet("All data stays in a local file on this Mac.")
                bullet("No account. No telemetry. No analytics.")
                bullet("No update checks — the app makes no network requests at all.")
                bullet("You can export or delete everything at any time.")
            }
            Spacer()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text(text)
        }
    }
}

private struct PermissionStep: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Input Monitoring permission")
                .font(.title.weight(.semibold))
            Text("To count keystrokes, macOS requires the Input Monitoring permission. ThoughtMeter uses it only to observe that a key went down — key identities are never read into storage, and nothing leaves this Mac.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: coordinator.trackingHealthy ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(coordinator.trackingHealthy ? .green : .orange)
                Text(coordinator.trackingHealthy ? "Granted and active"
                     : coordinator.permissionGranted ? "Granted but not active — toggle ThoughtMeter off and on in System Settings"
                     : "Not granted yet")
                    .font(.headline)
            }
            .padding(.vertical, 6)

            if !coordinator.trackingHealthy {
                HStack(spacing: 10) {
                    Button("Open System Settings") {
                        coordinator.permission.request()
                        PermissionMonitor.openSystemSettings()
                    }
                    Button("Recheck") { coordinator.permission.recheck() }
                }
                Text("In System Settings ▸ Privacy & Security ▸ Input Monitoring, enable ThoughtMeter. If macOS asks you to quit and reopen the app, onboarding will resume where you left off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("First launch note: ThoughtMeter is open-source and currently distributed without an Apple Developer certificate. If macOS blocked the first open, use right-click ▸ Open, or Privacy & Security ▸ “Open Anyway”. Never disable Gatekeeper system-wide for any app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SourcesStep: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What should count?")
                .font(.title.weight(.semibold))

            Picker("Mode", selection: Binding(
                get: { coordinator.settings.trackingMode },
                set: { coordinator.setTrackingMode($0) }
            )) {
                ForEach(TrackingMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(coordinator.settings.trackingMode == .selectedOnly
                 ? "Recommended. Only the tools you check below are counted."
                 : "Every recognized AI tool installed on this Mac is counted. You can still disable individual tools.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SourceChecklist()

            Text("Everything typed while a selected app is frontmost counts toward it — in Terminal that includes Claude Code, git, and ordinary shell commands alike. ThoughtMeter deliberately does not inspect what you typed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { coordinator.reloadSources() }
    }
}

/// Shared source list with enable toggles + add buttons (onboarding & settings).
struct SourceChecklist: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var newDomain = ""
    @State private var chromeWarningShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            List {
                Section("Applications") {
                    ForEach(coordinator.sources.filter { $0.kind == .app }) { source in
                        sourceRow(source)
                    }
                }
                Section("Chrome domains") {
                    ForEach(coordinator.sources.filter { $0.kind == .domain }) { source in
                        sourceRow(source)
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 180, maxHeight: 220)

            HStack(spacing: 8) {
                Button("Add App…") { pickApp() }
                TextField("Add domain (e.g. gemini.google.com)", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addDomain() }
                Button("Add") { addDomain() }
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.small)
        }
        .alert("Track Chrome through domains", isPresented: $chromeWarningShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Adding Chrome as an app would count typing on every website. Select the AI domains you want instead — ThoughtMeter's Chrome extension counts only those.")
        }
    }

    private func sourceRow(_ source: SourceRecord) -> some View {
        HStack(spacing: 8) {
            SourceIcon(source: source, size: 18)
            Toggle(isOn: Binding(
                get: { source.isEnabled },
                set: { coordinator.setSourceEnabled(source.id, enabled: $0) }
            )) {
                HStack(spacing: 6) {
                    Text(source.displayName)
                    if !source.isBuiltin {
                        Text("custom")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if !source.isBuiltin {
                Button {
                    coordinator.removeSource(source.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove this custom source and its history")
            }
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application to track"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if coordinator.addCustomApp(at: url) == .chromeRejected {
            chromeWarningShown = true
        }
    }

    private func addDomain() {
        let outcome = coordinator.addCustomDomain(newDomain)
        if outcome == .added { newDomain = "" }
    }
}

private struct LoginStep: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start automatically?")
                .font(.title.weight(.semibold))
            Text("ThoughtMeter only measures while it is running. If you want a complete daily picture, let it start when you log in. This is entirely optional and can be changed in Settings.")
                .foregroundStyle(.secondary)
            Toggle("Launch ThoughtMeter at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    coordinator.setLaunchAtLogin(newValue)
                }
                .padding(.top, 8)
            Spacer()
        }
        .onAppear { launchAtLogin = coordinator.launchAtLoginEnabled }
    }
}

private struct ChromeStep: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var installMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chrome websites (optional)")
                .font(.title.weight(.semibold))
            Text("To count typing on chatgpt.com or claude.ai — and nowhere else — ThoughtMeter needs its Chrome extension. The extension reports only the hostname of your active tab to this app, locally. It never reads page content and never contacts a server.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: coordinator.chromeConnected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(coordinator.chromeConnected ? .green : .secondary)
                Text(coordinator.chromeConnected ? "Extension connected" : "Extension not connected")
                    .font(.headline)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Register the local connector below.")
                Text("2. Install the ThoughtMeter Connector extension in Chrome — Settings ▸ Chrome has a guided 4-step setup.")
                Text("3. Come back here — the status updates automatically.")
            }
            .font(.callout)

            HStack(spacing: 10) {
                Button("Register Connector") {
                    do {
                        try NativeHostInstaller.install()
                        installMessage = "Connector registered. Now install the extension in Chrome."
                    } catch {
                        installMessage = String(describing: error)
                    }
                }
                Button("Retry Connection") { coordinator.refreshNow() }
            }
            if let installMessage {
                Text(installMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Text("You can skip this — desktop apps are tracked either way, and Chrome setup is always available in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
