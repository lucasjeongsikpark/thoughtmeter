import Foundation
import ThoughtMeterKit

private func makeStore(in directory: URL) throws -> SQLiteStore {
    try SQLiteStore(path: directory.appendingPathComponent("test.sqlite").path)
}

let storeTests: [TC] = [
    TC("upsert source is idempotent and preserves enabled flag") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let descriptor = SourceDescriptor(kind: .app, identifier: "com.apple.Terminal",
                                              displayName: "Terminal", isBuiltin: true)
            let id1 = try store.upsertSource(descriptor, now: 100)
            try store.setSourceEnabled(id: id1, enabled: false)
            let id2 = try store.upsertSource(descriptor, now: 200)
            t.expectEqual(id1, id2, "same identifier must reuse the row")
            let sources = try store.listSources()
            t.expectEqual(sources.count, 1)
            t.expect(!(sources[0].isEnabled), "user's disable must survive re-upsert")
        }
    },
    TC("activity upsert accumulates on duplicate bucket") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let id = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "a.b.c",
                                                             displayName: "C", isBuiltin: false), now: 0)
            let entry = SQLiteStore.ActivityEntry(bucketStart: 1200, sourceID: id, keystrokes: 5,
                                                  localDate: "2026-08-04", tzOffsetSeconds: -25200)
            try store.recordActivity([entry])
            try store.recordActivity([entry]) // same bucket again
            t.expectEqual(try store.totalKeystrokes(forLocalDate: "2026-08-04"), 10,
                          "duplicate bucket rows must accumulate, not duplicate")
        }
    },
    TC("totals by source and daily totals") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let vscode = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "com.microsoft.VSCode",
                                                                 displayName: "VS Code", isBuiltin: true), now: 0)
            let claude = try store.upsertSource(SourceDescriptor(kind: .domain, identifier: "claude.ai",
                                                                 displayName: "Claude (web)", isBuiltin: true), now: 0)
            try store.recordActivity([
                .init(bucketStart: 60, sourceID: vscode, keystrokes: 100, localDate: "2026-08-03", tzOffsetSeconds: 0),
                .init(bucketStart: 120, sourceID: claude, keystrokes: 40, localDate: "2026-08-03", tzOffsetSeconds: 0),
                .init(bucketStart: 86_460, sourceID: vscode, keystrokes: 7, localDate: "2026-08-04", tzOffsetSeconds: 0),
            ])
            let bySource = try store.totalsBySource(localDates: ["2026-08-03", "2026-08-04"])
            t.expectEqual(bySource.count, 2)
            t.expectEqual(bySource.first?.source.identifier, "com.microsoft.VSCode", "ordered by total desc")
            t.expectEqual(bySource.first?.keystrokes, 107)
            let daily = try store.dailyTotals(localDates: ["2026-08-03", "2026-08-04"])
            t.expectEqual(daily["2026-08-03"], 140)
            t.expectEqual(daily["2026-08-04"], 7)
        }
    },
    TC("hourly totals use stored tz offset") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let id = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "x.y.z",
                                                             displayName: "X", isBuiltin: false), now: 0)
            // bucket at 10:00 UTC with offset +2h → local hour 12
            let tenUTC: Int64 = 86_400 * 100 + 10 * 3600
            try store.recordActivity([
                .init(bucketStart: tenUTC, sourceID: id, keystrokes: 3,
                      localDate: "1970-04-11", tzOffsetSeconds: 7200)
            ])
            let hours = try store.hourlyTotals(forLocalDate: "1970-04-11")
            t.expectEqual(hours[12], 3)
            t.expectEqual(hours.reduce(0, +), 3)
        }
    },
    TC("hourly totals sum across several local dates") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let id = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "x.y.z",
                                                             displayName: "X", isBuiltin: false), now: 0)
            // Two days, same local hour 12 through different offsets — the
            // range's peak hour must add them, not pick one.
            let dayOne: Int64 = 86_400 * 100
            try store.recordActivity([
                // 10:00 UTC, +2h → local 12
                .init(bucketStart: dayOne + 10 * 3600, sourceID: id, keystrokes: 3,
                      localDate: "1970-04-11", tzOffsetSeconds: 7200),
                // 19:00 UTC, -7h → local 12 (next stored day)
                .init(bucketStart: dayOne + 86_400 + 19 * 3600, sourceID: id, keystrokes: 4,
                      localDate: "1970-04-12", tzOffsetSeconds: -25_200),
                // 08:00 UTC, +0 → local 8, one of the two days
                .init(bucketStart: dayOne + 8 * 3600, sourceID: id, keystrokes: 5,
                      localDate: "1970-04-11", tzOffsetSeconds: 0),
                // A day outside the requested range must not be counted.
                .init(bucketStart: dayOne + 3 * 86_400 + 12 * 3600, sourceID: id, keystrokes: 99,
                      localDate: "1970-04-14", tzOffsetSeconds: 0),
            ])
            let hours = try store.hourlyTotals(localDates: ["1970-04-11", "1970-04-12"])
            t.expectEqual(hours[12], 7, "same local hour on two days must sum")
            t.expectEqual(hours[8], 5)
            t.expectEqual(hours.reduce(0, +), 12, "dates outside the range are excluded")
            t.expectEqual(hours.count, 24)
        }
    },
    TC("hourly totals for no dates are all zero") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let hours = try store.hourlyTotals(localDates: [])
            t.expectEqual(hours.count, 24)
            t.expectEqual(hours.reduce(0, +), 0)
        }
    },
    TC("delete all activity keeps sources") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let id = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "a.b.c",
                                                             displayName: "C", isBuiltin: false), now: 0)
            try store.recordActivity([.init(bucketStart: 60, sourceID: id, keystrokes: 9,
                                            localDate: "2026-08-04", tzOffsetSeconds: 0)])
            try store.deleteAllActivity()
            t.expectEqual(try store.totalKeystrokes(forLocalDate: "2026-08-04"), 0)
            t.expectEqual(try store.listSources().count, 1, "source configuration preserved")
        }
    },
    TC("deleting a source cascades its activity") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let id = try store.upsertSource(SourceDescriptor(kind: .domain, identifier: "example.com",
                                                             displayName: "Example", isBuiltin: false), now: 0)
            try store.recordActivity([.init(bucketStart: 60, sourceID: id, keystrokes: 4,
                                            localDate: "2026-08-04", tzOffsetSeconds: 0)])
            try store.deleteSource(id: id)
            t.expectEqual(try store.totalKeystrokes(forLocalDate: "2026-08-04"), 0)
        }
    },
    TC("data persists across store reopen (simulated restart/update)") { t in
        try withTempDirectory { dir in
            let path = dir.appendingPathComponent("persist.sqlite").path
            do {
                let store = try SQLiteStore(path: path)
                let id = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "p.q.r",
                                                                 displayName: "PQR", isBuiltin: false), now: 0)
                try store.recordActivity([.init(bucketStart: 60, sourceID: id, keystrokes: 11,
                                                localDate: "2026-08-04", tzOffsetSeconds: 0)])
                store.close()
            }
            let reopened = try SQLiteStore(path: path)
            t.expectEqual(try reopened.totalKeystrokes(forLocalDate: "2026-08-04"), 11)
        }
    },
    TC("CSV export contains aggregate rows and header only") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let id = try store.upsertSource(SourceDescriptor(kind: .domain, identifier: "claude.ai",
                                                             displayName: "Claude (web)", isBuiltin: true), now: 0)
            try store.recordActivity([.init(bucketStart: 1_700_000_040, sourceID: id, keystrokes: 21,
                                            localDate: "2023-11-14", tzOffsetSeconds: 0)])
            let csv = try store.exportCSV()
            let lines = csv.split(separator: "\n")
            t.expectEqual(lines.count, 2, "header + one row")
            t.expect(lines[0].hasPrefix("bucket_start_utc,local_date,local_hour,source_kind"), "header shape")
            t.expect(lines[1].contains("claude.ai") && lines[1].contains(",21"), "row content")
        }
    },
    TC("activity for a deleted source is skipped, not failed") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let kept = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "kept.app",
                                                               displayName: "Kept", isBuiltin: false), now: 0)
            let doomed = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "doomed.app",
                                                                 displayName: "Doomed", isBuiltin: false), now: 0)
            try store.deleteSource(id: doomed)
            // A keystroke can land between a source's deletion and the
            // resolver recomputing — it must not poison the whole batch.
            try store.recordActivity([
                .init(bucketStart: 60, sourceID: kept, keystrokes: 3, localDate: "2026-08-05", tzOffsetSeconds: 0),
                .init(bucketStart: 60, sourceID: doomed, keystrokes: 9, localDate: "2026-08-05", tzOffsetSeconds: 0),
            ])
            t.expectEqual(try store.totalKeystrokes(forLocalDate: "2026-08-05"), 3,
                          "kept source persists; deleted source is dropped")
        }
    },
    TC("database file has owner-only permissions") { t in
        try withTempDirectory { dir in
            let path = dir.appendingPathComponent("perm.sqlite").path
            _ = try SQLiteStore(path: path)
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.int16Value ?? 0
            t.expectEqual(permissions & 0o777, 0o600)
        }
    },
    TC("WAL sidecars are owner-only too") { t in
        // -wal holds rows that have not been checkpointed into the database
        // yet: same user data, and SQLite creates it with the process umask.
        try withTempDirectory { dir in
            let path = dir.appendingPathComponent("wal.sqlite").path
            let store = try SQLiteStore(path: path)
            let source = try store.upsertSource(
                .init(kind: .app, identifier: "com.example.app", displayName: "Example", isBuiltin: false)
            )
            try store.recordActivity([
                .init(bucketStart: 0, sourceID: source, keystrokes: 5,
                      localDate: "2026-08-14", tzOffsetSeconds: 0),
            ])

            var checked = 0
            for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix) {
                let attributes = try FileManager.default.attributesOfItem(atPath: path + suffix)
                let permissions = (attributes[.posixPermissions] as? NSNumber)?.int16Value ?? 0
                t.expectEqual(permissions & 0o777, 0o600, "mode of \(path + suffix)")
                checked += 1
            }
            t.expect(checked >= 2, "expected the database and at least one WAL sidecar to exist, checked \(checked)")
        }
    },
    TC("an existing loose data directory is repaired to owner-only") { t in
        try withTempDirectory { dir in
            let base = dir.appendingPathComponent("ThoughtMeter", isDirectory: true)
            try FileManager.default.createDirectory(
                at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755]
            )
            let marker = base.appendingPathComponent("existing.txt")
            try Data("keep me".utf8).write(to: marker)

            _ = try SQLiteStore(path: base.appendingPathComponent("repair.sqlite").path)

            let attributes = try FileManager.default.attributesOfItem(atPath: base.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.int16Value ?? 0
            t.expectEqual(permissions & 0o777, 0o700, "pre-existing directory is tightened, not left at 0755")
            t.expect(FileManager.default.fileExists(atPath: marker.path),
                     "repairing permissions must not disturb existing data")
        }
    },
]

let flusherTests: [TC] = [
    TC("flush drains tracker into store with correct local date") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let id = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "f.g.h",
                                                             displayName: "FGH", isBuiltin: false), now: 0)
            // 2026-08-04 12:00:00 UTC
            let noonUTC: Int64 = 1_785_844_800
            let tracker = InputTracker(clock: { noonUTC })
            tracker.setActiveSource(id)
            tracker.handle(.keyDown(isAutoRepeat: false))
            tracker.handle(.keyDown(isAutoRepeat: false))
            let utc = LocalDateProvider(timeZone: TimeZone(identifier: "UTC")!)
            let flusher = AggregationFlusher(tracker: tracker, store: store, localDateProvider: { utc })
            try flusher.flush()
            let expectedDate = utc.localDateString(forUnixSeconds: noonUTC)
            t.expectEqual(try store.totalKeystrokes(forLocalDate: expectedDate), 2)
            t.expect(tracker.drain().isEmpty, "tracker drained")
        }
    },
    TC("midnight boundary splits across local dates (timezone aware)") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let id = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "m.n.o",
                                                             displayName: "MNO", isBuiltin: false), now: 0)
            // Tokyo (UTC+9): 2026-08-04 23:59:30 local = 14:59:30 UTC
            let beforeMidnightUTC: Int64 = 1_785_855_570
            var now = beforeMidnightUTC
            let tracker = InputTracker(clock: { now })
            tracker.setActiveSource(id)
            tracker.handle(.keyDown(isAutoRepeat: false))
            now += 60 // 00:00:30 local next day
            tracker.handle(.keyDown(isAutoRepeat: false))
            let tokyo = LocalDateProvider(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
            let flusher = AggregationFlusher(tracker: tracker, store: store, localDateProvider: { tokyo })
            try flusher.flush()
            t.expectEqual(try store.totalKeystrokes(forLocalDate: "2026-08-04"), 1)
            t.expectEqual(try store.totalKeystrokes(forLocalDate: "2026-08-05"), 1)
        }
    },
    TC("failed flush re-queues counts for the next cycle") { t in
        try withTempDirectory { dir in
            let store = try makeStore(in: dir)
            let id = try store.upsertSource(SourceDescriptor(kind: .app, identifier: "r.q.s",
                                                             displayName: "RQS", isBuiltin: false), now: 0)
            let tracker = InputTracker(clock: { 1_785_844_800 })
            tracker.setActiveSource(id)
            tracker.handle(.keyDown(isAutoRepeat: false))
            tracker.handle(.keyDown(isAutoRepeat: false))
            let utc = LocalDateProvider(timeZone: TimeZone(identifier: "UTC")!)
            let flusher = AggregationFlusher(tracker: tracker, store: store, localDateProvider: { utc })
            store.close() // force the write to fail
            do {
                try flusher.flush()
                t.fail("flush against a closed store must throw")
            } catch {}
            t.expectEqual(tracker.drain().values.reduce(0, +), 2,
                          "a failed flush must merge counts back, not drop them")
        }
    },
]
