import AppKit
import Testing
@testable import AICLILimits

private func snapshot(percent: Double, secondsLeft: TimeInterval, fetchedAt: Date = Date()) -> Snapshot {
    var s = Snapshot()
    s.session = UsageWindow(percent: percent, resetsAt: Date().addingTimeInterval(secondsLeft), length: 5 * 3600)
    s.fetchedAt = fetchedAt
    return s
}

@MainActor
private func title(_ readings: [Provider: Reading]) -> NSAttributedString {
    Store(fixed: readings).menuTitle
}

private func color(of text: NSAttributedString, at needle: String) -> NSColor? {
    let range = (text.string as NSString).range(of: needle)
    guard range.location != NSNotFound else { return nil }
    return text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
}

@Suite @MainActor struct MenuTitleTests {

    @Test func both_providers_with_percent_and_countdown() {
        // Half a minute of slack so the countdown does not round down mid-test.
        let text = title([
            .claude: .ok(snapshot(percent: 16, secondsLeft: 91 * 60 + 30)),
            .codex: .ok(snapshot(percent: 94, secondsLeft: 103 * 60 + 30)),
        ])
        #expect(text.string == "CC 16%·1h31  CDX 94%·1h43")
    }

    @Test func each_provider_is_coloured_on_its_own() {
        let text = title([
            .claude: .ok(snapshot(percent: 16, secondsLeft: 3600)),
            .codex: .ok(snapshot(percent: 94, secondsLeft: 3600)),
        ])
        #expect(color(of: text, at: "CC") == .labelColor)
        #expect(color(of: text, at: "CDX") == .systemOrange)
    }

    @Test func placeholders_for_the_states_without_numbers() {
        #expect(title([.claude: .loading, .codex: .signedOut]).string == "CC ·  CDX –")
        #expect(title([.claude: .failed("boom"), .codex: .ok(Snapshot())]).string == "CC ?  CDX –")
    }

    @Test func missing_provider_reads_as_loading() {
        #expect(title([:]).string == "CC ·  CDX ·")
    }

    @Test func old_stale_numbers_are_dimmed_unless_urgent() {
        let old = Date().addingTimeInterval(-20 * 60)
        let calm = snapshot(percent: 16, secondsLeft: 3600, fetchedAt: old)
        let hot = snapshot(percent: 96, secondsLeft: 3600, fetchedAt: old)
        let text = title([
            .claude: .stale(calm, since: old, note: "throttled"),
            .codex: .stale(hot, since: old, note: "throttled"),
        ])
        #expect(color(of: text, at: "CC") == .secondaryLabelColor)
        #expect(color(of: text, at: "CDX") == .systemRed)
    }

    @Test func recently_stale_numbers_keep_their_colour() {
        let recent = Date().addingTimeInterval(-5 * 60)
        let text = title([.claude: .stale(snapshot(percent: 16, secondsLeft: 3600), since: recent, note: "x")])
        #expect(color(of: text, at: "CC") == .labelColor)
    }
}
