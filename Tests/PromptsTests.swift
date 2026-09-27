import Foundation
import SQLite3
import Testing
@testable import AICLILimits

/// A throwaway directory, removed when the test is done with it.
private struct Scratch {
    let path: String
    init() throws {
        path = NSTemporaryDirectory() + "ai-cli-limits-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(atPath: path) }
}

private let start = Date(timeIntervalSince1970: 1_790_400_000)
private let end = start.addingTimeInterval(5 * 3600)

private func stamp(_ offset: TimeInterval) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: start.addingTimeInterval(offset))
}

@Suite struct ClaudeTranscriptTests {

    private func transcript(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

    @Test func counts_human_turns_inside_the_window_only() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let project = scratch.path + "/-Users-someone-work"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let lines = [
            // Typed by the person, in the window: counts.
            #"{"type":"user","timestamp":"\#(stamp(60))","message":{"role":"user","content":"hello"}}"#,
            #"{"type":"user","timestamp":"\#(stamp(600))","message":{"role":"user","content":[{"type":"text","text":"again"}]}}"#,
            // A tool result comes back with role user too: does not count.
            #"{"type":"user","timestamp":"\#(stamp(120))","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}"#,
            // Injected context is flagged isMeta: does not count.
            #"{"type":"user","isMeta":true,"timestamp":"\#(stamp(180))","message":{"role":"user","content":"context"}}"#,
            // The model's turns never count.
            #"{"type":"assistant","timestamp":"\#(stamp(200))","message":{"role":"assistant","content":"hi"}}"#,
            // Before the window opened, and after the reading was taken.
            #"{"type":"user","timestamp":"\#(stamp(-60))","message":{"role":"user","content":"old"}}"#,
            #"{"type":"user","timestamp":"\#(stamp(6 * 3600))","message":{"role":"user","content":"later"}}"#,
            // Not even JSON, which happens on a torn write.
            #"{"type":"user","timestamp":"#,
        ]
        try transcript(lines).write(toFile: project + "/session.jsonl", atomically: true, encoding: .utf8)
        try "ignored".write(toFile: project + "/notes.txt", atomically: true, encoding: .utf8)

        #expect(Prompts.claude(in: scratch.path, from: start, to: end) == 2)
    }

    @Test func sums_across_projects() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        for name in ["a", "b"] {
            let project = scratch.path + "/" + name
            try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
            let line = #"{"type":"user","timestamp":"\#(stamp(60))","message":{"role":"user","content":"x"}}"#
            try transcript([line, line]).write(toFile: project + "/t.jsonl", atomically: true, encoding: .utf8)
        }
        #expect(Prompts.claude(in: scratch.path, from: start, to: end) == 4)
    }

    @Test func transcripts_untouched_since_the_window_opened_are_skipped() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let project = scratch.path + "/p"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let file = project + "/t.jsonl"
        let line = #"{"type":"user","timestamp":"\#(stamp(60))","message":{"role":"user","content":"x"}}"#
        try transcript([line]).write(toFile: file, atomically: true, encoding: .utf8)
        // Pretend the file has not been written to since before the window.
        try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(-3600)], ofItemAtPath: file)

        // Nothing readable in the window at all reads as "no data", not zero.
        #expect(Prompts.claude(in: scratch.path, from: start, to: end) == nil)
    }

    @Test func missing_directory_is_no_data() {
        #expect(Prompts.claude(in: "/nonexistent/ai-cli-limits", from: start, to: end) == nil)
    }
}

@Suite struct CodexStoreTests {

    private func makeStore(at path: String, startedAt: [TimeInterval]) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let ddl = "create table thread_turns(id integer primary key, thread_id text, started_at integer)"
        try #require(sqlite3_exec(db, ddl, nil, nil, nil) == SQLITE_OK)
        for offset in startedAt {
            let at = Int64(start.addingTimeInterval(offset).timeIntervalSince1970)
            let sql = "insert into thread_turns(thread_id, started_at) values ('t', \(at))"
            try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
    }

    @Test func counts_turns_started_inside_the_window() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try makeStore(at: scratch.path + "/thread_history_v3.sqlite",
                      startedAt: [-10, 0, 60, 3600, 5 * 3600, 5 * 3600 + 1])
        // Both ends inclusive: the turn at the reset instant counts, one after it does not.
        #expect(Prompts.codex(in: scratch.path, from: start, to: end) == 4)
    }

    @Test func the_newest_schema_version_wins() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try makeStore(at: scratch.path + "/thread_history_v2.sqlite", startedAt: [60, 120, 180])
        try makeStore(at: scratch.path + "/thread_history_v3.sqlite", startedAt: [60])
        #expect(Prompts.codex(in: scratch.path, from: start, to: end) == 1)
    }

    @Test func no_store_is_no_data() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try "{}".write(toFile: scratch.path + "/auth.json", atomically: true, encoding: .utf8)
        #expect(Prompts.codex(in: scratch.path, from: start, to: end) == nil)
        #expect(Prompts.codex(in: "/nonexistent/ai-cli-limits", from: start, to: end) == nil)
    }

    @Test func a_store_without_the_table_is_no_data() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        var db: OpaquePointer?
        try #require(sqlite3_open(scratch.path + "/thread_history_v9.sqlite", &db) == SQLITE_OK)
        sqlite3_exec(db, "create table other(x)", nil, nil, nil)
        sqlite3_close(db)
        #expect(Prompts.codex(in: scratch.path, from: start, to: end) == nil)
    }
}
