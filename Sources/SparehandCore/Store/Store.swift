import Foundation
import SQLite3

/// Local SQLite storage: taps, when each tab URL was first seen, the undo journal and settings.
public final class Store: @unchecked Sendable {
    public enum StoreError: Error { case sqlite(String) }

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "dev.sparehand.store")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try open(path.path)
    }

    private init(memory: Void) throws { try open(":memory:") }

    public static func inMemory() throws -> Store { try Store(memory: ()) }

    deinit { sqlite3_close(db) }

    private func open(_ path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw StoreError.sqlite("open \(path)") }
        try exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS taps(id TEXT PRIMARY KEY, json BLOB NOT NULL, state TEXT NOT NULL, watcher TEXT NOT NULL, created_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS tab_seen(url TEXT PRIMARY KEY, first_seen REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS journal(id INTEGER PRIMARY KEY AUTOINCREMENT, tap_id TEXT NOT NULL, json BLOB NOT NULL, at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
    }

    public func upsert(_ tap: Tap) throws {
        let json = try encoder.encode(tap)
        try run("INSERT INTO taps(id, json, state, watcher, created_at) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json, state=excluded.state",
                [.text(tap.id), .blob(json), .text(tap.state.rawValue), .text(tap.candidate.watcher.rawValue), .real(tap.createdAt.timeIntervalSince1970)])
    }

    public func tap(id: String) throws -> Tap? {
        try query("SELECT json FROM taps WHERE id = ?", [.text(id)]) { try self.decoder.decode(Tap.self, from: $0.blob(0)) }.first
    }

    /// Taps in any of the given states, newest first.
    public func taps(states: Set<TapState>) throws -> [Tap] {
        guard !states.isEmpty else { return [] }
        let marks = Array(repeating: "?", count: states.count).joined(separator: ",")
        return try query("SELECT json FROM taps WHERE state IN (\(marks)) ORDER BY created_at DESC",
                         states.map { .text($0.rawValue) }) { try self.decoder.decode(Tap.self, from: $0.blob(0)) }
    }

    public func lastShown(watcher: WatcherID) throws -> Date? {
        try query("SELECT MAX(created_at) FROM taps WHERE watcher = ?", [.text(watcher.rawValue)]) { $0.isNull(0) ? nil : Date(timeIntervalSince1970: $0.real(0)) }.first ?? nil
    }

    /// When this URL was first seen open; records `now` the first time.
    public func firstSeen(url: URL, now: Date) throws -> Date {
        try run("INSERT OR IGNORE INTO tab_seen(url, first_seen) VALUES(?, ?)", [.text(url.absoluteString), .real(now.timeIntervalSince1970)])
        return try query("SELECT first_seen FROM tab_seen WHERE url = ?", [.text(url.absoluteString)]) { Date(timeIntervalSince1970: $0.real(0)) }.first ?? now
    }

    public func appendJournal(_ e: JournalEntry) throws {
        try run("INSERT INTO journal(tap_id, json, at) VALUES(?,?,?)", [.text(e.tapID), .blob(try encoder.encode(e)), .real(e.at.timeIntervalSince1970)])
    }

    /// Journal entries for a tap, oldest first.
    public func journal(tapID: String) throws -> [JournalEntry] {
        try query("SELECT json FROM journal WHERE tap_id = ? ORDER BY id", [.text(tapID)]) { try self.decoder.decode(JournalEntry.self, from: $0.blob(0)) }
    }

    public func setting(_ key: String) throws -> String? {
        try query("SELECT value FROM settings WHERE key = ?", [.text(key)]) { $0.text(0) }.first
    }

    public func setSetting(_ key: String, _ value: String) throws {
        try run("INSERT INTO settings(key, value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text(key), .text(value)])
    }

    // MARK: - SQLite plumbing

    enum Value { case text(String), blob(Data), real(Double) }

    struct Row {
        let stmt: OpaquePointer
        func text(_ i: Int32) -> String { String(cString: sqlite3_column_text(stmt, i)) }
        func real(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
        func blob(_ i: Int32) -> Data {
            guard let p = sqlite3_column_blob(stmt, i) else { return Data() }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func exec(_ sql: String) throws {
        try queue.sync {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.sqlite(String(cString: sqlite3_errmsg(db))) }
        }
    }

    private func run(_ sql: String, _ args: [Value]) throws {
        _ = try query(sql, args) { _ in () }
    }

    private func query<T>(_ sql: String, _ args: [Value], _ map: (Row) throws -> T) throws -> [T] {
        try queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            for (i, a) in args.enumerated() {
                let idx = Int32(i + 1)
                switch a {
                case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, Store.transient)
                case .real(let d): sqlite3_bind_double(stmt, idx, d)
                case .blob(let data): _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(data.count), Store.transient) }
                }
            }
            var out: [T] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW { out.append(try map(Row(stmt: stmt))) }
                else if rc == SQLITE_DONE { break }
                else { throw StoreError.sqlite(String(cString: sqlite3_errmsg(db))) }
            }
            return out
        }
    }
}
