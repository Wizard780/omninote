import Foundation
import SQLite3

public struct Note: Equatable {
    public var id: String
    public var created: Date
    public var lastModified: Date
    public var content: String
    public var dbIndex: Int  // larger = closer to the front of the stack
}

public enum StoreError: Error { case sqlite(String) }

/// Notes live in one SQLite file with the same column shape Antinote 1.x uses,
/// so its `notes` table can be imported with a plain `INSERT ... SELECT`.
public final class Store {
    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()

    public init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK { throw StoreError.sqlite(errorMessage) }
        try exec("""
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY NOT NULL,
            created TEXT NOT NULL,
            lastModified TEXT NOT NULL,
            content TEXT NOT NULL,
            dbIndex INTEGER NOT NULL UNIQUE
        )
        """)
    }

    deinit { sqlite3_close(db) }

    private var errorMessage: String { String(cString: sqlite3_errmsg(db)) }

    private func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw StoreError.sqlite(errorMessage) }
    }

    private func run(_ sql: String, _ args: [Any], row: ((OpaquePointer) -> Void)? = nil) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw StoreError.sqlite(errorMessage) }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            switch arg {
            case let s as String: sqlite3_bind_text(stmt, Int32(i + 1), s, -1, Store.transient)
            case let n as Int: sqlite3_bind_int64(stmt, Int32(i + 1), Int64(n))
            case let d as Date: sqlite3_bind_text(stmt, Int32(i + 1), Store.dateFormat.string(from: d), -1, Store.transient)
            default: fatalError("unsupported bind type")
            }
        }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { row?(stmt!) } else if rc == SQLITE_DONE { break } else { throw StoreError.sqlite(errorMessage) }
        }
    }

    private func notes(where clause: String = "", _ args: [Any] = []) throws -> [Note] {
        var out: [Note] = []
        try run("SELECT id, created, lastModified, content, dbIndex FROM notes \(clause) ORDER BY dbIndex DESC", args) { s in
            let text = { (i: Int32) in String(cString: sqlite3_column_text(s, i)) }
            out.append(Note(id: text(0),
                            created: Store.dateFormat.date(from: text(1)) ?? Date(),
                            lastModified: Store.dateFormat.date(from: text(2)) ?? Date(),
                            content: text(3),
                            dbIndex: Int(sqlite3_column_int64(s, 4))))
        }
        return out
    }

    /// Front of the stack first.
    public func all() throws -> [Note] { try notes() }

    public func search(_ term: String) throws -> [Note] {
        var escaped = term
        for c in ["\\", "%", "_"] { escaped = escaped.replacingOccurrences(of: c, with: "\\" + c) }
        return try notes(where: "WHERE content LIKE ? ESCAPE '\\'", ["%" + escaped + "%"])
    }

    private func nextIndex() throws -> Int {
        var max = 0
        try run("SELECT COALESCE(MAX(dbIndex), 0) FROM notes", []) { max = Int(sqlite3_column_int64($0, 0)) }
        return max + 1
    }

    @discardableResult
    public func create(content: String = "") throws -> Note {
        let now = Date()
        let note = Note(id: UUID().uuidString, created: now, lastModified: now, content: content, dbIndex: try nextIndex())
        try run("INSERT INTO notes (id, created, lastModified, content, dbIndex) VALUES (?, ?, ?, ?, ?)",
                [note.id, note.created, note.lastModified, note.content, note.dbIndex])
        return note
    }

    public func save(id: String, content: String) throws {
        try run("UPDATE notes SET content = ?, lastModified = ? WHERE id = ?", [content, Date(), id])
    }

    public func delete(id: String) throws { try run("DELETE FROM notes WHERE id = ?", [id]) }

    /// Move a note to the front of the stack.
    public func promote(id: String) throws {
        try run("UPDATE notes SET dbIndex = ? WHERE id = ?", [try nextIndex(), id])
    }

    /// Antinote's "auto-delete unmodified notes". Returns how many were removed.
    @discardableResult
    public func deleteUnmodified(before cutoff: Date) throws -> Int {
        try run("DELETE FROM notes WHERE lastModified < ?", [cutoff])
        return Int(sqlite3_changes(db))
    }
}
