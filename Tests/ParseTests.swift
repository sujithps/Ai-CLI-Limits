import Foundation
import Testing
@testable import AICLILimits

private func json(_ text: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

@Suite struct DateParsingTests {

    @Test func unix_seconds_as_int_or_double() {
        #expect(Fetch.date(1_800_000_000) == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(Fetch.date(1_800_000_000.5) == Date(timeIntervalSince1970: 1_800_000_000.5))
    }

    @Test func iso_with_microseconds_is_trimmed_not_rejected() throws {
        let date = try #require(Fetch.date("2026-09-28T07:00:00.299530+00:00"))
        #expect(abs(date.timeIntervalSince1970 - 1_790_578_800.299) < 0.001)
    }

    @Test func iso_with_and_without_fraction() {
        #expect(Fetch.date("2026-09-28T07:00:00Z") == Date(timeIntervalSince1970: 1_790_578_800))
        #expect(Fetch.date("2026-09-28T07:00:00.5Z") == Date(timeIntervalSince1970: 1_790_578_800.5))
    }

    @Test func garbage_is_nil() {
        #expect(Fetch.date(nil) == nil)
        #expect(Fetch.date("yesterday") == nil)
        #expect(Fetch.date(true) == nil)
    }
}

@Suite struct ClaudeParsingTests {

    static let utilization = """
    {
      "five_hour": {"utilization": 16, "resets_at": "2026-09-27T15:30:00.299530+00:00",
                    "limit_dollars": null, "used_dollars": null},
      "seven_day": {"utilization": 47, "resets_at": "2026-09-28T07:00:00Z"},
      "seven_day_opus": null
    }
    """

    @Test func both_windows_with_their_fixed_lengths() throws {
        let snapshot = Fetch.claudeSnapshot(try json(Self.utilization), plan: "team")
        let session = try #require(snapshot.session)
        let weekly = try #require(snapshot.weekly)
        #expect(session.percent == 16)
        #expect(session.length == 5 * 3600)
        #expect(session.resetsAt == Fetch.date("2026-09-27T15:30:00.299Z"))
        #expect(weekly.percent == 47)
        #expect(weekly.length == 7 * 86_400)
        #expect(snapshot.plan == "team")
        #expect(snapshot.promptsUsed == nil)
        #expect(snapshot.models.isEmpty)
    }

    @Test func missing_windows_are_nil_rather_than_zero() throws {
        let snapshot = Fetch.claudeSnapshot(try json(#"{"five_hour": {"utilization": 3}}"#), plan: nil)
        #expect(snapshot.session?.percent == 3)
        #expect(snapshot.session?.resetsAt == nil)
        #expect(snapshot.weekly == nil)
    }

    @Test func cache_file_carries_its_read_time_and_plan() throws {
        let root = try json("""
        {
          "oauthAccount": {"organizationType": "claude_team"},
          "cachedUsageUtilization": {
            "fetchedAtMs": 1790479373443,
            "utilization": \(Self.utilization)
          }
        }
        """)
        let before = Date(timeIntervalSince1970: 1_790_500_000)
        let cached = try #require(Fetch.claudeCached(root, now: before))
        #expect(cached.snapshot.fetchedAt == Date(timeIntervalSince1970: 1_790_479_373.443))
        #expect(cached.snapshot.plan == "team")
        #expect(cached.windowAlive)
    }

    @Test func cache_is_dead_once_its_window_has_reset() throws {
        let root = try json("""
        {"cachedUsageUtilization": {"fetchedAtMs": 1790479373443, "utilization": \(Self.utilization)}}
        """)
        let after = Date(timeIntervalSince1970: 1_790_600_000)
        let cached = try #require(Fetch.claudeCached(root, now: after))
        #expect(!cached.windowAlive)
        #expect(cached.snapshot.plan == nil)
    }

    @Test func cache_is_alive_when_nothing_has_been_used_yet() throws {
        // Before the first prompt of a window Claude reports 0% and no reset time.
        let root = try json("""
        {"cachedUsageUtilization": {"fetchedAtMs": 1790479373443,
          "utilization": {"five_hour": {"utilization": 0, "resets_at": null}}}}
        """)
        let cached = try #require(Fetch.claudeCached(root))
        #expect(cached.windowAlive)
    }

    @Test func cache_is_dead_when_used_but_the_reset_time_is_missing() throws {
        let root = try json("""
        {"cachedUsageUtilization": {"fetchedAtMs": 1790479373443,
          "utilization": {"five_hour": {"utilization": 20, "resets_at": null}}}}
        """)
        let cached = try #require(Fetch.claudeCached(root))
        #expect(!cached.windowAlive)
    }

    @Test func cache_without_the_expected_keys_is_nil() throws {
        #expect(Fetch.claudeCached(try json(#"{"cachedUsageUtilization": {"fetchedAtMs": 1}}"#)) == nil)
        #expect(Fetch.claudeCached(try json(#"{"numStartups": 4}"#)) == nil)
    }
}

@Suite struct CodexParsingTests {

    static let usage = """
    {
      "plan_type": "team",
      "rate_limit": {
        "primary_window":   {"used_percent": 94, "limit_window_seconds": 18000, "reset_at": 1790500000},
        "secondary_window": {"used_percent": 62, "reset_at": 1790800000}
      },
      "model_usage": {
        "gpt-6-astra": {"available": true},
        "gpt-6-astra-mini": {"available": false, "available_at": 1790510000},
        "gpt-6-astra-nano": {"available": false}
      },
      "credits": {"approx_local_messages": null}
    }
    """

    @Test func windows_take_the_reported_length_or_the_fallback() throws {
        let snapshot = Fetch.codexSnapshot(try json(Self.usage))
        let session = try #require(snapshot.session)
        let weekly = try #require(snapshot.weekly)
        #expect(session.percent == 94)
        #expect(session.length == 18_000)
        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_790_500_000))
        #expect(weekly.percent == 62)
        #expect(weekly.length == 7 * 86_400)
        #expect(snapshot.plan == "team")
        #expect(snapshot.promptsUsed == nil)
    }

    @Test func models_are_sorted_by_name_with_their_return_time() throws {
        let models = Fetch.codexSnapshot(try json(Self.usage)).models
        #expect(models.map(\.name) == ["gpt-6-astra", "gpt-6-astra-mini", "gpt-6-astra-nano"])
        #expect(models.map(\.available) == [true, false, false])
        #expect(models[1].availableAt == Date(timeIntervalSince1970: 1_790_510_000))
        #expect(models[2].availableAt == nil)
    }

    @Test func an_empty_body_is_an_empty_snapshot_not_a_crash() throws {
        let snapshot = Fetch.codexSnapshot(try json("{}"))
        #expect(snapshot.session == nil)
        #expect(snapshot.weekly == nil)
        #expect(snapshot.plan == nil)
        #expect(snapshot.models.isEmpty)
    }
}
