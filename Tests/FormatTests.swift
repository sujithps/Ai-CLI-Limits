import AppKit
import Testing
@testable import AICLILimits

@Suite struct SpanTests {

    @Test func hours_and_minutes() {
        #expect(Fmt.span(5400) == "1h 30m")
        #expect(Fmt.span(5400, tight: true) == "1h30")
        #expect(Fmt.span(3600 + 5 * 60) == "1h 05m")
        #expect(Fmt.span(3600 + 5 * 60, tight: true) == "1h05")
    }

    @Test func days_drop_the_minutes() {
        #expect(Fmt.span(90_000) == "1d 1h")
        #expect(Fmt.span(90_000, tight: true) == "1d1h")
    }

    @Test func minutes_alone() {
        #expect(Fmt.span(300) == "5m")
        #expect(Fmt.span(300, tight: true) == "5m")
    }

    @Test func under_a_minute() {
        #expect(Fmt.span(45) == "under a minute")
        #expect(Fmt.span(45, tight: true) == "<1m")
        #expect(Fmt.span(0) == "under a minute")
    }

    @Test func rounds_to_the_nearest_second_first() {
        #expect(Fmt.span(59.6, tight: true) == "1m")
    }
}

@Suite struct NumberFormatTests {

    @Test func percent_rounds_to_a_whole_number() {
        #expect(Fmt.percent(16.4) == "16%")
        #expect(Fmt.percent(16.5) == "17%")
        #expect(Fmt.percent(0) == "0%")
    }

    @Test func coarse_keeps_small_numbers_exact() {
        #expect(Fmt.coarse(0) == 0)
        #expect(Fmt.coarse(7) == 7)
        #expect(Fmt.coarse(19) == 19)
    }

    @Test func coarse_rounds_to_fives_under_a_hundred() {
        #expect(Fmt.coarse(21) == 20)
        #expect(Fmt.coarse(23) == 25)
        #expect(Fmt.coarse(99) == 100)
    }

    @Test func coarse_rounds_to_tens_from_a_hundred() {
        #expect(Fmt.coarse(100) == 100)
        #expect(Fmt.coarse(212) == 210)
        #expect(Fmt.coarse(276) == 280)
    }
}

@Suite struct MenuColorTests {

    @Test func each_pressure_has_its_colour() {
        #expect(Fmt.menuColor(.calm) == .labelColor)
        #expect(Fmt.menuColor(.opportunity) == .systemGreen)
        #expect(Fmt.menuColor(.warning) == .systemOrange)
        #expect(Fmt.menuColor(.critical) == .systemRed)
    }
}
