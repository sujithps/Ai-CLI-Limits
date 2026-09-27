import Foundation
import Testing
@testable import AICLILimits

private let hour: TimeInterval = 3600

/// A 5-hour window that started `elapsed` seconds ago.
private func session(percent: Double, elapsed: TimeInterval, now: Date = Date()) -> UsageWindow {
    UsageWindow(percent: percent, resetsAt: now.addingTimeInterval(5 * hour - elapsed), length: 5 * hour)
}

@Suite struct UsageWindowTests {

    @Test func start_is_reset_minus_length() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let window = UsageWindow(percent: 10, resetsAt: reset, length: 5 * hour)
        #expect(window.start == reset.addingTimeInterval(-5 * hour))
    }

    @Test func remaining_never_goes_negative() {
        let past = UsageWindow(percent: 10, resetsAt: Date().addingTimeInterval(-60), length: 5 * hour)
        #expect(past.remaining == 0)
        let none = UsageWindow(percent: 10, resetsAt: nil, length: 5 * hour)
        #expect(none.remaining == nil)
        #expect(none.start == nil)
    }

    @Test func unused_is_the_rest_of_the_window_and_floors_at_zero() {
        #expect(session(percent: 30, elapsed: hour).unused == 70)
        #expect(session(percent: 130, elapsed: hour).unused == 0)
    }

    @Test func burnout_projects_from_the_rate_so_far() throws {
        // 90% gone after three of five hours: the remaining 10% lasts 20 minutes.
        let window = session(percent: 90, elapsed: 3 * hour)
        let eta = try #require(window.burnout)
        #expect(abs(eta.timeIntervalSinceNow - 20 * 60) < 5)
    }

    @Test func burnout_is_nil_when_the_pace_lands_past_the_reset() {
        #expect(session(percent: 30, elapsed: 3 * hour).burnout == nil)
    }

    @Test func burnout_is_nil_too_early_in_the_window() {
        // Five minutes in, any rate is noise, however high the percentage.
        #expect(session(percent: 40, elapsed: 5 * 60).burnout == nil)
    }

    @Test func burnout_is_nil_at_or_under_one_percent() {
        #expect(session(percent: 1, elapsed: 4 * hour).burnout == nil)
    }
}

@Suite struct PromptsLeftTests {

    private func snapshot(percent: Double, used: Int?) -> Snapshot {
        var s = Snapshot()
        s.session = session(percent: percent, elapsed: hour)
        s.promptsUsed = used
        return s
    }

    @Test func range_brackets_the_rounding_on_the_percentage() throws {
        // The README's own example: 10 prompts at 4%, so the true cost is
        // anywhere in 3.5-4.5% and the answer is a range.
        let left = try #require(snapshot(percent: 4, used: 10).promptsLeft)
        #expect(left.low == 212)
        #expect(left.high == 276)
    }

    @Test func nothing_is_said_below_two_percent() {
        #expect(snapshot(percent: 1, used: 10).promptsLeft == nil)
        #expect(snapshot(percent: 2, used: 10).promptsLeft != nil)
    }

    @Test func nothing_is_said_without_a_prompt_count() {
        #expect(snapshot(percent: 40, used: nil).promptsLeft == nil)
        #expect(snapshot(percent: 40, used: 0).promptsLeft == nil)
    }

    @Test func range_collapses_to_zero_at_the_limit() throws {
        let left = try #require(snapshot(percent: 100, used: 50).promptsLeft)
        #expect(left.low == 0)
        #expect(left.high == 0)
    }
}

@Suite struct PressureTests {

    private func snapshot(session: UsageWindow?, weekly: UsageWindow? = nil) -> Snapshot {
        var s = Snapshot()
        s.session = session
        s.weekly = weekly
        return s
    }

    @Test func calm_by_default() {
        #expect(snapshot(session: nil).pressure == .calm)
        #expect(snapshot(session: session(percent: 50, elapsed: hour)).pressure == .calm)
    }

    @Test func session_thresholds() {
        #expect(snapshot(session: session(percent: 79, elapsed: hour)).pressure == .calm)
        #expect(snapshot(session: session(percent: 80, elapsed: hour)).pressure == .warning)
        #expect(snapshot(session: session(percent: 94, elapsed: hour)).pressure == .warning)
        #expect(snapshot(session: session(percent: 95, elapsed: hour)).pressure == .critical)
    }

    @Test func opportunity_needs_a_close_reset_and_plenty_unused() {
        let closing = session(percent: 50, elapsed: 5 * hour - 20 * 60)
        #expect(snapshot(session: closing).pressure == .opportunity)
        // Same timing, but only 30% unused: not worth a nudge.
        let spent = session(percent: 70, elapsed: 5 * hour - 20 * 60)
        #expect(snapshot(session: spent).pressure == .calm)
        // Plenty unused, but 40 minutes to go: not yet.
        let early = session(percent: 50, elapsed: 5 * hour - 40 * 60)
        #expect(snapshot(session: early).pressure == .calm)
    }

    @Test func weekly_can_raise_but_never_lower() {
        let week = { (p: Double) in UsageWindow(percent: p, resetsAt: Date().addingTimeInterval(3 * 86_400), length: 7 * 86_400) }
        #expect(snapshot(session: session(percent: 10, elapsed: hour), weekly: week(80)).pressure == .warning)
        #expect(snapshot(session: session(percent: 10, elapsed: hour), weekly: week(90)).pressure == .critical)
        #expect(snapshot(session: session(percent: 96, elapsed: hour), weekly: week(10)).pressure == .critical)
        #expect(snapshot(session: nil, weekly: week(79)).pressure == .calm)
    }

    @Test func pressure_orders_by_urgency() {
        #expect(Pressure.calm < .opportunity)
        #expect(Pressure.opportunity < .warning)
        #expect(Pressure.warning < .critical)
    }
}
