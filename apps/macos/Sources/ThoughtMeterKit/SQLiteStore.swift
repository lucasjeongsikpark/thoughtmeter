import Foundation
import SQLite3

/// Persistence for sources and minute-bucketed activity counts.
///
/// Uses the system SQLite library directly. All access is serialized on a
/// private queue; every public method is synchronous and thread-safe.
/// The database stores ONLY aggregate counts and source identifiers —
/// never key values, URLs, titles, or content (see PRIVACY.md).
public final class SQLiteStore {
    public enum StoreError: Error, CustomStringConvertible {
        case openFailed(String)
        case sqlError(String)
        case closed

        public var description: String {
            switch self {
            case .openFailed(let m): return "Could not open database: \(m)"
            case .sqlError(let m): return "Database error: \(m)"
            case .closed: return "Database is closed"
            }
        }
    }

    public struct ActivityEntry {
        public let bucketStart: Int64
        public let sourceID: Int64
        public let keystrokes: Int
        public let localDate: String
        public let tzOffsetSeconds: Int

        public init(bucketStart: Int64, sourceID: Int64, keystrokes: Int,
                    localDate: String, tzOffsetSeconds: Int) {
            self.bucketStart = bucketStart
            self.sourceID = sourceID
            self.keystrokes = keystrokes
            self.localDate = localDate
            self.tzOffsetSeconds = tzOffsetSeconds
        }
    }

    private let queue = DispatchQueue(label: "org.thoughtmeter.sqlite")
    private var db: OpaquePointer?
    public let path: String

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        self.path = path
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // createDirectory's attributes apply only when it actually creates the
        // directory: for one that already exists it is a silent no-op, so a
        // directory created by an older build (or loosened by hand) would keep
        // its old mode forever.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory
        )
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h = handle { sqlite3_close_v2(h) }
            throw StoreError.openFailed(message)
        }
        db = opened
        try queue.sync {
            try execLocked("PRAGMA journal_mode=WAL")
            try execLocked("PRAGMA foreign_keys=ON")
            try execLocked("PRAGMA synchronous=NORMAL")
            try migrateLocked()
        }
        hardenFilePermissions()
    }

    /// Owner-only permissions on the database AND its WAL sidecars.
    ///
    /// PRIVACY.md promises owner-only files, and `-wal` holds recently written
    /// rows that have not been checkpointed yet — it is the same user data as
    /// the main database, and SQLite creates it with the process umask rather
    /// than inheriting the database's mode. Called after open and again after
    /// operations that can recreate the sidecars.
    func hardenFilePermissions() {
        let manager = FileManager.default
        for candidate in [path, path + "-wal", path + "-shm"]
        where manager.fileExists(atPath: candidate) {
            do {
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: candidate)
            } catch {
                // Not fatal: counting must keep working on a filesystem that
                // cannot represent these modes. Visible rather than silent.
                NSLog("ThoughtMeter: could not restrict permissions on \(candidate) — \(error)")
            }
        }
    }

    deinit { close() }

    public func close() {
        queue.sync {
            if let handle = db {
                sqlite3_close_v2(handle)
                db = nil
            }
        }
    }

    // MARK: - Schema

    private func migrateLocked() throws {
        let version = try scalarLocked("PRAGMA user_version") ?? 0
        if version < 1 {
            try execLocked("""
            CREATE TABLE IF NOT EXISTS sources(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL CHECK(kind IN ('app','domain')),
                identifier TEXT NOT NULL,
                display_name TEXT NOT NULL,
                is_builtin INTEGER NOT NULL DEFAULT 0,
                is_enabled INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL,
                UNIQUE(kind, identifier)
            )
            """)
            try execLocked("""
            CREATE TABLE IF NOT EXISTS activity(
                bucket_utc_start INTEGER NOT NULL,
                local_date TEXT NOT NULL,
                tz_offset_seconds INTEGER NOT NULL,
                source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
                keystrokes INTEGER NOT NULL CHECK(keystrokes >= 0),
                PRIMARY KEY(bucket_utc_start, source_id)
            ) WITHOUT ROWID
            """)
            try execLocked("CREATE INDEX IF NOT EXISTS idx_activity_local_date ON activity(local_date)")
            try execLocked("PRAGMA user_version = 1")
        }
    }

    // MARK: - Sources

    /// Insert a source or return the existing one's id. An existing source's
    /// enabled flag is never changed here (a user's explicit disable must
    /// survive re-detection in "All recognized tools" mode).
    /// `enabledOnInsert` controls only brand-new rows: "Selected tools only"
    /// mode inserts detected sources disabled until the user opts in.
    @discardableResult
    public func upsertSource(_ descriptor: SourceDescriptor,
                             enabledOnInsert: Bool = true,
                             now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> Int64 {
        try queue.sync {
            let sql = """
            INSERT INTO sources(kind, identifier, display_name, is_builtin, is_enabled, created_at)
            VALUES(?,?,?,?,?,?)
            ON CONFLICT(kind, identifier) DO UPDATE SET display_name = excluded.display_name
            RETURNING id
            """
            let statement = try prepareLocked(sql)
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, descriptor.kind.rawValue)
            bindText(statement, 2, descriptor.identifier)
            bindText(statement, 3, descriptor.displayName)
            sqlite3_bind_int64(statement, 4, descriptor.isBuiltin ? 1 : 0)
            sqlite3_bind_int64(statement, 5, enabledOnInsert ? 1 : 0)
            sqlite3_bind_int64(statement, 6, now)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw StoreError.sqlError(lastMessageLocked())
            }
            return sqlite3_column_int64(statement, 0)
        }
    }

    public func listSources() throws -> [SourceRecord] {
        try queue.sync {
            let sql = """
            SELECT id, kind, identifier, display_name, is_builtin, is_enabled, created_at
            FROM sources ORDER BY display_name COLLATE NOCASE
            """
            let statement = try prepareLocked(sql)
            defer { sqlite3_finalize(statement) }
            var records: [SourceRecord] = []
            try stepRowsLocked(statement) {
                if let record = readSourceRow(statement) { records.append(record) }
            }
            return records
        }
    }

    public func setSourceEnabled(id: Int64, enabled: Bool) throws {
        try queue.sync {
            let statement = try prepareLocked("UPDATE sources SET is_enabled=? WHERE id=?")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, enabled ? 1 : 0)
            sqlite3_bind_int64(statement, 2, id)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.sqlError(lastMessageLocked())
            }
        }
    }

    /// Remove a source and (via cascade) its recorded activity.
    public func deleteSource(id: Int64) throws {
        try queue.sync {
            let statement = try prepareLocked("DELETE FROM sources WHERE id=?")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.sqlError(lastMessageLocked())
            }
        }
    }

    // MARK: - Activity

    /// Batched, transactional upsert. Duplicate (bucket, source) rows are
    /// accumulated, never duplicated.
    ///
    /// Entries whose source no longer exists are skipped, not failed: a
    /// keystroke can land between a source's deletion and the resolver
    /// recomputing, and its history is cascade-deleted anyway — failing the
    /// whole batch (and every retry of it) over such an entry would wedge
    /// flushing permanently.
    public func recordActivity(_ entries: [ActivityEntry]) throws {
        guard !entries.isEmpty else { return }
        try queue.sync {
            try execLocked("BEGIN IMMEDIATE")
            do {
                let sql = """
                INSERT INTO activity(bucket_utc_start, local_date, tz_offset_seconds, source_id, keystrokes)
                SELECT ?,?,?,?,?
                WHERE EXISTS(SELECT 1 FROM sources WHERE id = ?4)
                ON CONFLICT(bucket_utc_start, source_id)
                DO UPDATE SET keystrokes = keystrokes + excluded.keystrokes
                """
                let statement = try prepareLocked(sql)
                defer { sqlite3_finalize(statement) }
                for entry in entries {
                    sqlite3_reset(statement)
                    sqlite3_bind_int64(statement, 1, entry.bucketStart)
                    bindText(statement, 2, entry.localDate)
                    sqlite3_bind_int64(statement, 3, Int64(entry.tzOffsetSeconds))
                    sqlite3_bind_int64(statement, 4, entry.sourceID)
                    sqlite3_bind_int64(statement, 5, Int64(entry.keystrokes))
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw StoreError.sqlError(lastMessageLocked())
                    }
                }
                try execLocked("COMMIT")
            } catch {
                try? execLocked("ROLLBACK")
                throw error
            }
        }
        // SQLite creates -wal/-shm lazily, on the first write, using the
        // process umask — so the mode set at open cannot cover them.
        hardenFilePermissions()
    }

    // MARK: - Queries

    public func totalKeystrokes(forLocalDate date: String) throws -> Int {
        try queue.sync {
            let statement = try prepareLocked("SELECT COALESCE(SUM(keystrokes),0) FROM activity WHERE local_date=?")
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, date)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw StoreError.sqlError(lastMessageLocked())
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    /// Keystrokes per local hour (0–23) for one local date. Uses the timezone
    /// offset stored at recording time, so history stays correct after moves.
    public func hourlyTotals(forLocalDate date: String) throws -> [Int] {
        try queue.sync {
            let sql = """
            SELECT ((bucket_utc_start + tz_offset_seconds) % 86400) / 3600 AS hour, SUM(keystrokes)
            FROM activity WHERE local_date=? GROUP BY hour
            """
            let statement = try prepareLocked(sql)
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, date)
            var hours = [Int](repeating: 0, count: 24)
            try stepRowsLocked(statement) {
                let hour = Int(sqlite3_column_int64(statement, 0))
                if (0..<24).contains(hour) {
                    hours[hour] = Int(sqlite3_column_int64(statement, 1))
                }
            }
            return hours
        }
    }

    public func totalsBySource(localDates: [String]) throws -> [(source: SourceRecord, keystrokes: Int)] {
        guard !localDates.isEmpty else { return [] }
        return try queue.sync {
            let placeholders = Array(repeating: "?", count: localDates.count).joined(separator: ",")
            let sql = """
            SELECT s.id, s.kind, s.identifier, s.display_name, s.is_builtin, s.is_enabled, s.created_at,
                   SUM(a.keystrokes) AS total
            FROM activity a JOIN sources s ON s.id = a.source_id
            WHERE a.local_date IN (\(placeholders))
            GROUP BY s.id ORDER BY total DESC
            """
            let statement = try prepareLocked(sql)
            defer { sqlite3_finalize(statement) }
            for (index, date) in localDates.enumerated() {
                bindText(statement, Int32(index + 1), date)
            }
            var results: [(SourceRecord, Int)] = []
            try stepRowsLocked(statement) {
                if let record = readSourceRow(statement) {
                    results.append((record, Int(sqlite3_column_int64(statement, 7))))
                }
            }
            return results
        }
    }

    public func dailyTotals(localDates: [String]) throws -> [String: Int] {
        guard !localDates.isEmpty else { return [:] }
        return try queue.sync {
            let placeholders = Array(repeating: "?", count: localDates.count).joined(separator: ",")
            let sql = "SELECT local_date, SUM(keystrokes) FROM activity WHERE local_date IN (\(placeholders)) GROUP BY local_date"
            let statement = try prepareLocked(sql)
            defer { sqlite3_finalize(statement) }
            for (index, date) in localDates.enumerated() {
                bindText(statement, Int32(index + 1), date)
            }
            var totals: [String: Int] = [:]
            try stepRowsLocked(statement) {
                if let cString = sqlite3_column_text(statement, 0) {
                    totals[String(cString: cString)] = Int(sqlite3_column_int64(statement, 1))
                }
            }
            return totals
        }
    }

    // MARK: - Data lifecycle

    /// Delete all recorded activity. Source configuration is preserved
    /// (the confirmation dialog states this explicitly).
    public func deleteAllActivity() throws {
        try queue.sync {
            try execLocked("DELETE FROM activity")
            try execLocked("VACUUM")
        }
    }

    /// Export all activity as CSV. Aggregate counts only.
    public func exportCSV() throws -> String {
        try queue.sync {
            let sql = """
            SELECT a.bucket_utc_start, a.local_date, ((a.bucket_utc_start + a.tz_offset_seconds) % 86400) / 3600,
                   s.kind, s.identifier, s.display_name, a.keystrokes
            FROM activity a JOIN sources s ON s.id = a.source_id
            ORDER BY a.bucket_utc_start, s.identifier
            """
            let statement = try prepareLocked(sql)
            defer { sqlite3_finalize(statement) }
            var csv = "bucket_start_utc,local_date,local_hour,source_kind,source_identifier,source_name,keystrokes\n"
            let iso = ISO8601DateFormatter()
            try stepRowsLocked(statement) {
                let bucket = sqlite3_column_int64(statement, 0)
                let date = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let hour = sqlite3_column_int64(statement, 2)
                let kind = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                let identifier = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let name = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
                let keystrokes = sqlite3_column_int64(statement, 6)
                let timestamp = iso.string(from: Date(timeIntervalSince1970: TimeInterval(bucket)))
                csv += "\(timestamp),\(date),\(hour),\(kind),\(csvEscape(identifier)),\(csvEscape(name)),\(keystrokes)\n"
            }
            return csv
        }
    }

    public func databaseFileSize() -> Int64 {
        let manager = FileManager.default
        var total: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            if let attributes = try? manager.attributesOfItem(atPath: path + suffix),
               let size = attributes[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    // MARK: - Internals (must run on queue)

    private func requireDBLocked() throws -> OpaquePointer {
        guard let handle = db else { throw StoreError.closed }
        return handle
    }

    private func execLocked(_ sql: String) throws {
        let handle = try requireDBLocked()
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw StoreError.sqlError(message)
        }
    }

    private func scalarLocked(_ sql: String) throws -> Int64? {
        let statement = try prepareLocked(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private func prepareLocked(_ sql: String) throws -> OpaquePointer {
        let handle = try requireDBLocked()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else {
            throw StoreError.sqlError(lastMessageLocked())
        }
        return prepared
    }

    /// Step through all result rows, then verify the scan finished cleanly.
    /// sqlite3_step reports mid-scan I/O errors through its return code;
    /// treating anything != SQLITE_ROW as end-of-rows would silently
    /// truncate results (worst case: an incomplete CSV backup).
    private func stepRowsLocked(_ statement: OpaquePointer, _ row: () -> Void) throws {
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            row()
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            throw StoreError.sqlError(lastMessageLocked())
        }
    }

    private func lastMessageLocked() -> String {
        guard let handle = db else { return "database closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    private func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func readSourceRow(_ statement: OpaquePointer) -> SourceRecord? {
        guard
            let kindCString = sqlite3_column_text(statement, 1),
            let kind = SourceKind(rawValue: String(cString: kindCString)),
            let identifierCString = sqlite3_column_text(statement, 2),
            let nameCString = sqlite3_column_text(statement, 3)
        else { return nil }
        return SourceRecord(
            id: sqlite3_column_int64(statement, 0),
            kind: kind,
            identifier: String(cString: identifierCString),
            displayName: String(cString: nameCString),
            isBuiltin: sqlite3_column_int64(statement, 4) != 0,
            isEnabled: sqlite3_column_int64(statement, 5) != 0,
            createdAt: sqlite3_column_int64(statement, 6)
        )
    }

    private func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
