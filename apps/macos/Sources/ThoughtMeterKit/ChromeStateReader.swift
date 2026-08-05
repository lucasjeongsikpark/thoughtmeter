import Foundation

/// Watches the Chrome state file the native host writes and keeps the latest
/// state cached in memory. The keyboard hot path never reads this file —
/// changes arrive asynchronously and are pushed to the SourceResolver.
///
/// Watches the *directory* (the host replaces the file via atomic rename,
/// which would invalidate a file-descriptor watch on the old inode).
public final class ChromeStateReader {
    private let stateURL: URL
    private let queue = DispatchQueue(label: "org.thoughtmeter.chromestate")
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1
    private let lock = NSLock()
    private var cached: ChromeDomainState?

    /// Called on `queue` whenever the state changes (including to nil).
    public var onChange: ((ChromeDomainState?) -> Void)?

    public init(stateURL: URL = DataPaths.chromeStateURL) {
        self.stateURL = stateURL
    }

    deinit { stop() }

    public var currentState: ChromeDomainState? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.reload()
            self.installWatcher()
        }
    }

    public func stop() {
        directorySource?.cancel()
        directorySource = nil
    }

    /// Re-read the state file and notify if it changed. Safe to call anytime.
    public func refresh() {
        queue.async { [weak self] in self?.reload() }
    }

    private func installWatcher() {
        let directory = stateURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        directoryDescriptor = open(directory.path, O_EVTONLY)
        guard directoryDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { [descriptor = directoryDescriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        directorySource = source
    }

    private func reload() {
        let newState = AtomicFile.readJSON(ChromeDomainState.self, from: stateURL)
        lock.lock()
        let changed = newState != cached
        cached = newState
        lock.unlock()
        if changed { onChange?(newState) }
    }
}

/// Writes the selected-domain config the native host reads.
public enum ChromeConfigWriter {
    public static func write(domains: [String],
                             to url: URL = DataPaths.chromeConfigURL,
                             now: Int64 = Int64(Date().timeIntervalSince1970)) throws {
        let config = ChromeHostConfig(domains: domains.sorted(), updatedAt: now)
        try AtomicFile.writeJSON(config, to: url)
    }
}
