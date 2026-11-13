import Foundation
import SQLite3

/// Queue-confined, per-file incremental index. No paths or conversation text are stored.
final class TokenActivityIndex {
    typealias ScopedFile = CodexTokenActivityService.ScopedFile
    typealias CachedFile = CodexTokenActivityService.CachedFile
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private struct DatabaseError: Error {}

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(database)
            database = nil
            throw DatabaseError()
        }
        do {
            sqlite3_busy_timeout(database, 1000)
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA auto_vacuum = INCREMENTAL")
            try execute("""
                CREATE TABLE IF NOT EXISTS files (
                    file_key TEXT PRIMARY KEY, home_scope TEXT NOT NULL,
                    modified REAL NOT NULL, size INTEGER NOT NULL, created REAL NOT NULL,
                    offset INTEGER NOT NULL, previous REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS events (
                    file_key TEXT NOT NULL REFERENCES files(file_key) ON DELETE CASCADE,
                    event_key TEXT NOT NULL, date_id TEXT NOT NULL, tokens REAL NOT NULL,
                    PRIMARY KEY(file_key, event_key));
                """)
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try work(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }

    func metadata() throws -> [String: ScopedFile] {
        let statement = try prepare("SELECT file_key, home_scope, modified, size, created, offset, previous FROM files")
        defer { sqlite3_finalize(statement) }
        var result: [String: ScopedFile] = [:]
        while try step(statement) {
            result[string(statement, 0)] = ScopedFile(homeScope: string(statement, 1), file: CachedFile(
                modified: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2)),
                size: Int(sqlite3_column_int64(statement, 3)),
                created: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 4)),
                offset: UInt64(sqlite3_column_int64(statement, 5)),
                previous: sqlite3_column_double(statement, 6), events: []))
        }
        return result
    }

    func update(key: String, value: ScopedFile, replacingEvents: Bool) throws {
        let statement = try prepare("""
            INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_key) DO UPDATE SET home_scope=excluded.home_scope,
                modified=excluded.modified, size=excluded.size, created=excluded.created,
                offset=excluded.offset, previous=excluded.previous
            """)
        defer { sqlite3_finalize(statement) }
        let file = value.file
        bind(key, to: statement, at: 1)
        bind(value.homeScope, to: statement, at: 2)
        sqlite3_bind_double(statement, 3, file.modified.timeIntervalSinceReferenceDate)
        sqlite3_bind_int64(statement, 4, Int64(file.size))
        sqlite3_bind_double(statement, 5, file.created.timeIntervalSinceReferenceDate)
        sqlite3_bind_int64(statement, 6, Int64(file.offset))
        sqlite3_bind_double(statement, 7, file.previous)
        _ = try step(statement)
        if replacingEvents { try delete("events", key: key) }
        let insert = try prepare("INSERT OR IGNORE INTO events VALUES (?, ?, ?, ?)")
        defer { sqlite3_finalize(insert) }
        for event in file.events {
            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
            bind(key, to: insert, at: 1)
            bind(event.key, to: insert, at: 2)
            bind(event.dateID, to: insert, at: 3)
            sqlite3_bind_double(insert, 4, event.tokens)
            _ = try step(insert)
        }
    }

    func remove(keys: Set<String>) throws {
        for key in keys { try delete("files", key: key) }
    }

    func records() throws -> [ActivityDay] {
        let statement = try prepare("""
            SELECT date_id, SUM(tokens) FROM (
                SELECT f.home_scope, e.event_key, e.date_id, MAX(e.tokens) AS tokens
                FROM events e JOIN files f ON f.file_key=e.file_key
                GROUP BY f.home_scope, e.event_key, e.date_id
            ) GROUP BY date_id ORDER BY date_id
            """)
        defer { sqlite3_finalize(statement) }
        var result: [ActivityDay] = []
        while try step(statement) {
            result.append(ActivityDay(dateID: string(statement, 0), value: sqlite3_column_double(statement, 1)))
        }
        return result
    }

    private func delete(_ table: String, key: String) throws {
        let statement = try prepare("DELETE FROM \(table) WHERE file_key = ?")
        defer { sqlite3_finalize(statement) }
        bind(key, to: statement, at: 1)
        _ = try step(statement)
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        String(cString: sqlite3_column_text(statement, column))
    }

    private func step(_ statement: OpaquePointer) throws -> Bool {
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW || status == SQLITE_DONE else { throw DatabaseError() }
        return status == SQLITE_ROW
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw DatabaseError() }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError() }
    }
}
