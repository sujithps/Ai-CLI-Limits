import AppKit
import Foundation
import SwiftUI

enum Fmt {

    /// "2h 14m", "48m", "3d 4h". Menu-bar variant drops the space.
    static func span(_ seconds: TimeInterval, tight: Bool = false) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return tight ? "<1m" : "under a minute" }
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        let gap = tight ? "" : " "
        if days > 0 { return "\(days)d\(gap)\(hours)h" }
        if hours > 0 {
            let mm = String(format: "%02d", minutes)
            return tight ? "\(hours)h\(mm)" : "\(hours)h \(mm)m"
        }
        return "\(minutes)m"
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current)
        return f
    }()

    static let dayClock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEjmm", options: 0, locale: .current)
        return f
    }()

    /// Same-day resets read as a time; anything further out carries its weekday.
    static func moment(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? clock.string(from: date) : dayClock.string(from: date)
    }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    /// Drops precision the estimate does not have, so 234 does not read as a
    /// measurement when it is a division of two rounded numbers.
    static func coarse(_ n: Int) -> Int {
        switch n {
        case ..<20: return n
        case ..<100: return (n + 2) / 5 * 5
        default: return (n + 5) / 10 * 10
        }
    }

    /// labelColor for the calm case so the title keeps tracking a light or
    /// dark menu bar instead of being pinned to one.
    static func menuColor(_ pressure: Pressure) -> NSColor {
        switch pressure {
        case .calm: return .labelColor
        case .opportunity: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    static let menuFont: NSFont = .monospacedDigitSystemFont(
        ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

    /// Same thresholds as `Pressure`, so a number in the panel and a colour in
    /// the menu bar never disagree about how bad things are.
    static func tint(_ percent: Double) -> Color {
        switch percent {
        case ..<80: return .primary.opacity(0.85)
        case ..<95: return .orange
        default: return .red
        }
    }
}
