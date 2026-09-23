import Foundation
import SQLite3

/// Counts prompts each CLI recorded inside a rate-limit window.
///
/// Neither provider reports tokens or prompts remaining, so this is the only
/// way to turn a percentage into something countable: divide the window's
/// measured cost by the number of prompts that caused it. Both halves are real
/// numbers, the provider's own utilization and this machine's own logs.
enum Prompts {

    static func used(by provider: Provider, from start: Date, to end: Date) -> Int? {
        switch provider {
        case .claude: return claude(from: start, to: end)
        case .codex: return codex(from: start, to: end)
        }
    }

    // MARK: Claude Code

    /// Transcript lines typed by the person, as opposed to tool results and
    /// injected context, which are also recorded with role "user".
    private static func claude(from start: Date, to end: Date) -> Int? {
        let root = NSHomeDirectory() + "/.claude/projects"
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(atPath: root) else { return nil }

        var count = 0
        var readAnything = false
        for project in projects {
            let dir = root + "/" + project
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".jsonl") {
                let path = dir + "/" + name
                guard let touched = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                      touched >= start else { continue }
                readAnything = true
                count += humanTurns(inTranscript: path, from: start, to: end)
            }
        }
        return readAnything ? count : nil
    }

    private static func humanTurns(inTranscript path: String, from start: Date, to end: Date) -> Int {
        guard let data = FileManager.default.contents(atPath: path) else { return 0 }
        var count = 0
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard line.contains(asciiUserMarker) else { continue }
            guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  entry["type"] as? String == "user",
                  entry["isMeta"] as? Bool != true,
                  let stamp = Fetch.date(entry["timestamp"]),
                  stamp >= start, stamp <= end else { continue }
            let body = (entry["message"] as? [String: Any])?["content"]
            if let blocks = body as? [[String: Any]],
               blocks.contains(where: { $0["type"] as? String == "tool_result" }) { continue }
            count += 1
        }
        return count
    }

    /// `"type":"user"` as raw bytes, to skip JSON parsing on most lines.
    private static let asciiUserMarker = Array(#""type":"user""#.utf8)

    // MARK: Codex

    /// One row per prompt in the CLI's thread store, counted by start time: a
    /// turn still running has already spent quota. The filename carries a
    /// schema version, so take the newest rather than pinning to one.
    private static func codex(from start: Date, to end: Date) -> Int? {
        let dir = NSHomeDirectory() + "/.codex"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        guard let store = names
            .filter({ $0.hasPrefix("thread_history_") && $0.hasSuffix(".sqlite") })
            .sorted().last else { return nil }

        let path = dir + "/" + store
        if let direct = turns(inStore: path, readOnly: true, from: start, to: end) { return direct }

        // A write-ahead-log database cannot reliably be opened read-only:
        // SQLite has to touch the -shm file and is not allowed to. Counting a
        // private copy avoids writing anything into the Codex directory.
        guard let copy = privateCopy(of: path) else { return nil }
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        return turns(inStore: copy.path, readOnly: false, from: start, to: end)
    }

    private static func turns(inStore path: String, readOnly: Bool,
                              from start: Date, to end: Date) -> Int? {
        var db: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "select count(*) from thread_turns where started_at between ? and ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(start.timeIntervalSince1970))
        sqlite3_bind_int64(statement, 2, Int64(end.timeIntervalSince1970))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// The -wal travels with the database, or the copy loses recent turns. The
    /// -shm deliberately does not: SQLite rebuilds it, and a stale one copied
    /// mid-write makes it refuse to open the database at all.
    private static func privateCopy(of path: String) -> URL? {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("limits-codex-\(UUID().uuidString)")
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return nil }

        let target = dir.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
        do {
            try fm.copyItem(at: URL(fileURLWithPath: path), to: target)
        } catch {
            try? fm.removeItem(at: dir)
            return nil
        }
        if fm.fileExists(atPath: path + "-wal") {
            try? fm.copyItem(at: URL(fileURLWithPath: path + "-wal"),
                             to: URL(fileURLWithPath: target.path + "-wal"))
        }
        return target
    }
}
