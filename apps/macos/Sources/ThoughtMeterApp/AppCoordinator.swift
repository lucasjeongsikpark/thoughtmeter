import AppKit
import Combine
import ServiceManagement
import SwiftUI
import ThoughtMeterKit

enum MenuBarIconState {
    case active
    case paused
    case noPermission
    case chromeDisconnected
}

/// Wires ThoughtMeterKit services together and publishes UI state.
/// Lives for the whole app lifetime.
@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    // MARK: Services
    let settings = AppSettings()
    let permission = PermissionMonitor()
    private let tracker = InputTracker()
    private let resolver = SourceResolver()
    private(set) var store: SQLiteStore?
    private var flusher: AggregationFlusher?
    private let chromeReader = ChromeStateReader()
    private let frontmost = FrontmostAppMonitor()
    private let eventSource = EventTapSource()
    private var flushTimer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var started = false

    // MARK: Published UI state
    @Published private(set) var sources: [SourceRecord] = []
    @Published private(set) var todayTotal = 0
    @Published private(set) var todayBySource: [(source: SourceRecord, keystrokes: Int)] = []
    @Published private(set) var currentSourceName: String?
    @Published private(set) var pauseState: AppSettings.PauseState = .active
    @Published private(set) var chromeConnected = false
    @Published private(set) var permissionGranted = false
    @Published var startupError: String?

    var isPaused: Bool { pauseState != .active }

    /// True when at least one enabled domain source exists — only then is a
    /// disconnected Chrome extension worth surfacing.
    var chromeRelevant: Bool {
        sources.contains { $0.kind == .domain && $0.isEnabled }
    }

    var menuBarIconState: MenuBarIconState {
        if !permissionGranted { return .noPermission }
        if isPaused { return .paused }
        if chromeRelevant && !chromeConnected { return .chromeDisconnected }
        return .active
    }

    var menuBarText: String? {
        switch settings.menuBarDisplay {
        case .iconOnly, .iconHiddenCount: return nil
        case .iconCompactCount: return HumanInputFormatter.compact(todayTotal)
        case .iconRawCount: return HumanInputFormatter.exact(todayTotal)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        do {
            try DataPaths.ensureDirectories()
            let store = try SQLiteStore(path: DataPaths.databaseURL.path)
            self.store = store
            self.flusher = AggregationFlusher(tracker: tracker, store: store)
        } catch {
            startupError = "ThoughtMeter could not open its local database: \(error)"
            return
        }

        seedRecognizedSources()
        reloadSources()

        frontmost.onChange = { [weak self] _ in
            Task { @MainActor in self?.recomputeActiveSource() }
        }
        frontmost.start()

        chromeReader.onChange = { [weak self] _ in
            Task { @MainActor in
                self?.recomputeActiveSource()
                self?.refreshChromeStatus()
            }
        }
        chromeReader.start()

        eventSource.onEvent = { [tracker] event in
            tracker.handle(event) // hot path: no main-thread hop
        }

        permission.onGranted = { [weak self] in
            Task { @MainActor in self?.startEventTap() }
        }
        permissionGranted = permission.granted
        if permission.granted {
            startEventTap()
        } else {
            permission.startPollingIfNeeded()
        }
        permission.$granted
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in self?.permissionGranted = granted }
            .store(in: &cancellables)

        // Periodic flush + UI refresh. Also re-evaluates pause expiry and
        // Chrome state freshness (both are time-based, not event-based).
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        installLifecycleObservers()
        applyPauseState()
        recomputeActiveSource()
        refreshStats()
        refreshChromeStatus()
    }

    func shutdown() {
        flushQuietly()
        eventSource.stop()
        chromeReader.stop()
        frontmost.stop()
        flushTimer?.invalidate()
        store?.close()
    }

    private var cancellables: Set<AnyCancellable> = []

    private func installLifecycleObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        lifecycleObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.flushQuietly() }
        })
        lifecycleObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
    }

    private func tick() {
        flushQuietly()
        applyPauseState()
        recomputeActiveSource() // Chrome freshness can expire without an event
        refreshStats()
        refreshChromeStatus()
    }

    private func startEventTap() {
        do {
            tracker.resetModifierState()
            try eventSource.start()
        } catch {
            // Tap creation fails when permission is missing/revoked.
            permission.startPollingIfNeeded()
        }
    }

    // MARK: - Sources

    /// Insert recognized, installed apps and recognized domains.
    /// New rows start enabled only in "All recognized" mode; existing rows
    /// keep the user's enabled/disabled choice.
    private func seedRecognizedSources() {
        guard let store else { return }
        let enableNew = settings.trackingMode == .allRecognized
        for app in InstalledApps.detectedRecognizedApps() {
            let descriptor = SourceDescriptor(kind: .app, identifier: app.bundleID,
                                              displayName: app.displayName, isBuiltin: true)
            _ = try? store.upsertSource(descriptor, enabledOnInsert: enableNew)
        }
        for (name, domain) in RecognizedCatalog.domains {
            let descriptor = SourceDescriptor(kind: .domain, identifier: domain,
                                              displayName: name, isBuiltin: true)
            _ = try? store.upsertSource(descriptor, enabledOnInsert: enableNew)
        }
    }

    func reloadSources() {
        guard let store else { return }
        sources = (try? store.listSources()) ?? []
        resolver.updateEnabledSources(sources)
        try? ChromeConfigWriter.write(domains: resolver.enabledDomains())
        recomputeActiveSource()
        refreshStats()
    }

    func setSourceEnabled(_ id: Int64, enabled: Bool) {
        try? store?.setSourceEnabled(id: id, enabled: enabled)
        reloadSources()
    }

    func removeSource(_ id: Int64) {
        flushQuietly()
        try? store?.deleteSource(id: id)
        reloadSources()
    }

    enum AddSourceOutcome: Equatable {
        case added
        case chromeRejected
        case invalid
    }

    /// Add a user-picked application. Chrome is refused: it must be tracked
    /// through selected domains, otherwise every website would count.
    func addCustomApp(at url: URL) -> AddSourceOutcome {
        guard let app = InstalledApps.inspect(appAt: url) else { return .invalid }
        if RecognizedCatalog.isChrome(bundleID: app.bundleID) { return .chromeRejected }
        let isRecognized = RecognizedCatalog.apps.contains { $0.bundleID == app.bundleID }
        let descriptor = SourceDescriptor(kind: .app, identifier: app.bundleID,
                                          displayName: app.displayName, isBuiltin: isRecognized)
        guard let id = try? store?.upsertSource(descriptor, enabledOnInsert: true) else { return .invalid }
        try? store?.setSourceEnabled(id: id, enabled: true)
        reloadSources()
        return .added
    }

    func addCustomDomain(_ raw: String) -> AddSourceOutcome {
        guard let domain = DomainNormalizer.normalize(raw) else { return .invalid }
        let isRecognized = RecognizedCatalog.domains.contains { $0.domain == domain }
        let descriptor = SourceDescriptor(kind: .domain, identifier: domain,
                                          displayName: domain, isBuiltin: isRecognized)
        guard let id = try? store?.upsertSource(descriptor, enabledOnInsert: true) else { return .invalid }
        try? store?.setSourceEnabled(id: id, enabled: true)
        reloadSources()
        return .added
    }

    func setTrackingMode(_ mode: TrackingMode) {
        settings.trackingMode = mode
        if mode == .allRecognized {
            // "All recognized" means: everything in the built-in list that is
            // installed gets tracked. Individual disables remain possible after.
            seedRecognizedSources()
            for source in (try? store?.listSources()) ?? [] where source.isBuiltin && !source.isEnabled {
                try? store?.setSourceEnabled(id: source.id, enabled: true)
            }
        }
        reloadSources()
        objectWillChange.send()
    }

    // MARK: - Tracking state

    private func recomputeActiveSource() {
        let sourceID = resolver.resolve(
            frontmostBundleID: frontmost.currentBundleID,
            chromeState: chromeReader.currentState
        )
        tracker.setActiveSource(sourceID)
        if let sourceID, let source = sources.first(where: { $0.id == sourceID }) {
            currentSourceName = source.displayName
        } else {
            currentSourceName = nil
        }
    }

    private func applyPauseState() {
        pauseState = settings.pauseState()
        tracker.setPaused(pauseState != .active)
    }

    func pause(for interval: TimeInterval?) {
        let now = Int64(Date().timeIntervalSince1970)
        if let interval {
            settings.setPausedUntil(now + Int64(interval))
        } else {
            settings.setPausedUntil(nil) // indefinite
        }
        flushQuietly()
        applyPauseState()
        objectWillChange.send()
    }

    func pauseUntilTomorrow() {
        settings.setPausedUntil(LocalDateProvider().startOfTomorrow())
        flushQuietly()
        applyPauseState()
        objectWillChange.send()
    }

    func resumeTracking() {
        settings.resume()
        applyPauseState()
        objectWillChange.send()
    }

    var pauseDescription: String {
        switch pauseState {
        case .active:
            return "Active"
        case .pausedIndefinitely:
            return "Paused"
        case .pausedUntil(let until):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "Paused until \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(until))))"
        }
    }

    // MARK: - Stats

    private func refreshStats() {
        guard let store else { return }
        let provider = LocalDateProvider()
        let today = provider.localDateString(forUnixSeconds: Int64(Date().timeIntervalSince1970))
        let dbTotal = (try? store.totalKeystrokes(forLocalDate: today)) ?? 0
        var bySource = (try? store.totalsBySource(localDates: [today])) ?? []

        // Merge not-yet-flushed counts so the popover feels live.
        let pending = tracker.pendingTotalsBySource()
        if !pending.isEmpty {
            var indexByID: [Int64: Int] = [:]
            for (index, entry) in bySource.enumerated() { indexByID[entry.source.id] = index }
            for (sourceID, count) in pending {
                if let index = indexByID[sourceID] {
                    bySource[index].keystrokes += count
                } else if let source = sources.first(where: { $0.id == sourceID }) {
                    bySource.append((source, count))
                }
            }
            bySource.sort { $0.keystrokes > $1.keystrokes }
        }
        todayTotal = dbTotal + pending.values.reduce(0, +)
        todayBySource = bySource
    }

    /// Public refresh for views appearing (popover open, dashboard open).
    func refreshNow() {
        tick()
    }

    private func refreshChromeStatus() {
        let now = Int64(Date().timeIntervalSince1970)
        chromeConnected = chromeReader.currentState?.isFresh(now: now) ?? false
    }

    var chromeStateDescription: String {
        guard let state = chromeReader.currentState else {
            return "No connection yet"
        }
        let now = Int64(Date().timeIntervalSince1970)
        guard state.isFresh(now: now) else { return "Stale (extension not responding)" }
        if let domain = state.trackedDomain {
            return "Connected — active tab: \(domain)"
        }
        return "Connected — current site not tracked"
    }

    private func flushQuietly() {
        do {
            try flusher?.flush()
        } catch {
            // Counts stay pending in memory; the next cycle retries.
            NSLog("ThoughtMeter flush failed: %@", String(describing: error))
        }
    }

    // MARK: - Data controls

    func exportCSV() {
        flushQuietly()
        guard let store else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ThoughtMeter-export.csv"
        panel.title = "Export Human Input data"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let csv = try store.exportCSV()
            try csv.data(using: .utf8)?.write(to: url)
        } catch {
            presentError("Export failed: \(error)")
        }
    }

    func deleteAllData() {
        flushQuietly()
        _ = tracker.drain() // discard anything pending
        do {
            try store?.deleteAllActivity()
        } catch {
            presentError("Could not delete data: \(error)")
        }
        refreshStats()
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([DataPaths.baseDirectory])
    }

    var storageUsageDescription: String {
        let bytes = store?.databaseFileSize() ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Launch at login

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            presentError("Could not update the login item: \(error)")
        }
        objectWillChange.send()
    }

    // MARK: - Onboarding

    func finishOnboarding() {
        settings.onboardingComplete = true
        reloadSources()
        objectWillChange.send()
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "ThoughtMeter"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
