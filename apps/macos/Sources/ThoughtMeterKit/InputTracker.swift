import Foundation

/// The hot path. Receives every keyboard event, decides whether it counts,
/// and increments an in-memory counter keyed by (minute bucket, source).
///
/// Performance contract (see ARCHITECTURE): `handle(_:)` takes a lock,
/// updates modifier state, possibly increments one dictionary entry, and
/// returns. It never touches disk, never reads files, never allocates
/// beyond the dictionary insert.
public final class InputTracker {
    public struct BucketKey: Hashable {
        /// Unix seconds, aligned to the start of a UTC minute.
        public let minuteStart: Int64
        public let sourceID: Int64

        public init(minuteStart: Int64, sourceID: Int64) {
            self.minuteStart = minuteStart
            self.sourceID = sourceID
        }
    }

    private let lock = NSLock()
    private let counter = KeystrokeCounter()
    private var activeSourceID: Int64?
    private var paused = false
    private var pending: [BucketKey: Int] = [:]
    private let now: () -> Int64

    /// - Parameter clock: injectable unix-seconds clock for tests.
    ///   The default uses time(2) — integer seconds with no Date/Double
    ///   round-trip, since this runs once per keystroke.
    public init(clock: @escaping () -> Int64 = { Int64(time(nil)) }) {
        self.now = clock
    }

    /// Called from the event tap callback for every observed keyboard event.
    public func handle(_ event: KeyEventKind) {
        lock.lock()
        defer { lock.unlock() }
        // Modifier state must advance even when paused or untracked,
        // otherwise a modifier held across a pause would count on resume.
        let counts = counter.shouldCount(event)
        guard counts, !paused, let sourceID = activeSourceID else { return }
        let minute = (now() / 60) * 60
        pending[BucketKey(minuteStart: minute, sourceID: sourceID), default: 0] += 1
    }

    /// Set by SourceResolver whenever the frontmost app / Chrome domain /
    /// configuration changes. nil means "do not count".
    public func setActiveSource(_ sourceID: Int64?) {
        lock.lock()
        activeSourceID = sourceID
        lock.unlock()
    }

    public func setPaused(_ isPaused: Bool) {
        lock.lock()
        paused = isPaused
        lock.unlock()
    }

    /// Remove and return all pending counts (called by the flush scheduler).
    public func drain() -> [BucketKey: Int] {
        lock.lock()
        defer { lock.unlock() }
        let drained = pending
        pending = [:]
        return drained
    }

    /// Pending (not yet flushed) totals per source, for live UI display.
    public func pendingTotalsBySource() -> [Int64: Int] {
        lock.lock()
        defer { lock.unlock() }
        var totals: [Int64: Int] = [:]
        for (key, count) in pending {
            totals[key.sourceID, default: 0] += count
        }
        return totals
    }

    /// Reset modifier tracking (event tap restarted).
    public func resetModifierState() {
        lock.lock()
        counter.reset()
        lock.unlock()
    }
}
