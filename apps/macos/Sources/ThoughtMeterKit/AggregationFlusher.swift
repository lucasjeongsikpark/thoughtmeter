import Foundation

/// Drains the InputTracker's in-memory counters into SQLite.
///
/// Called by the app on a ~30 second timer and at lifecycle boundaries
/// (sleep, quit, day change, pause, export, before destructive operations).
/// Each bucket keeps the local date / timezone offset of its own minute.
public final class AggregationFlusher {
    private let tracker: InputTracker
    private let store: SQLiteStore
    private let localDate: () -> LocalDateProvider

    /// - Parameter localDateProvider: evaluated at flush time so timezone
    ///   changes are picked up without restarting.
    public init(tracker: InputTracker,
                store: SQLiteStore,
                localDateProvider: @escaping () -> LocalDateProvider = { LocalDateProvider() }) {
        self.tracker = tracker
        self.store = store
        self.localDate = localDateProvider
    }

    /// Persist all pending counts in one transaction.
    /// On failure, drained counts are merged back into the tracker so the
    /// next cycle retries them; a crash loses at most the pending window
    /// (bounded, documented).
    public func flush() throws {
        let drained = tracker.drain()
        guard !drained.isEmpty else { return }
        let provider = localDate()
        let entries = drained.map { key, count in
            SQLiteStore.ActivityEntry(
                bucketStart: key.minuteStart,
                sourceID: key.sourceID,
                keystrokes: count,
                localDate: provider.localDateString(forUnixSeconds: key.minuteStart),
                tzOffsetSeconds: provider.tzOffsetSeconds(forUnixSeconds: key.minuteStart)
            )
        }
        do {
            try store.recordActivity(entries)
        } catch {
            tracker.requeue(drained)
            throw error
        }
    }
}
