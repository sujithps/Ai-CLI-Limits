import Foundation

enum Provider: String, CaseIterable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    var title: String { self == .claude ? "Claude Code" : "Codex" }
    var badge: String { self == .claude ? "CC" : "CDX" }
}

/// One rate-limit window as both providers report it: a percentage used and
/// the instant it rolls over. Window length is fixed per window kind, which is
/// what lets us work backwards to a start time and a burn rate.
struct UsageWindow: Codable {
    var percent: Double
    var resetsAt: Date?
    var length: TimeInterval

    var start: Date? { resetsAt.map { $0.addingTimeInterval(-length) } }

    var remaining: TimeInterval? {
        guard let r = resetsAt else { return nil }
        return max(r.timeIntervalSinceNow, 0)
    }

    var unused: Double { max(0, 100 - percent) }

    /// When the window empties if the current rate holds. Nil when too little
    /// of the window has elapsed for the rate to mean anything, or when the
    /// pace lands past the reset anyway. A tenth of the window is the floor:
    /// ten minutes into a seven-day window the projection is pure noise.
    var burnout: Date? {
        guard let start, let resetsAt, percent > 1 else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > max(600, length * 0.1) else { return nil }
        let perSecond = percent / elapsed
        guard perSecond > 0 else { return nil }
        let eta = Date().addingTimeInterval(unused / perSecond)
        return eta < resetsAt ? eta : nil
    }
}

struct ModelStatus: Codable, Identifiable {
    var id: String { name }
    var name: String
    var available: Bool
    var availableAt: Date?
}

/// How much the menu bar should say about a provider without being opened.
/// `opportunity` is the inverse of a warning: quota you are about to lose by
/// not spending it.
enum Pressure: Int, Comparable {
    case calm = 0, opportunity, warning, critical

    static func < (a: Pressure, b: Pressure) -> Bool { a.rawValue < b.rawValue }
}

struct Snapshot: Codable {
    var session: UsageWindow?
    var weekly: UsageWindow?
    var plan: String?
    var models: [ModelStatus] = []
    var fetchedAt = Date()
    /// Prompts this machine logged inside the session window, counted at the
    /// same instant as `session.percent` so the two can be divided.
    var promptsUsed: Int?

    /// Prompts still available this window, bracketed by the rounding on the
    /// percentage. Providers report whole numbers, so at 2% the true figure is
    /// anywhere in 1.5-2.5% and the answer is a range, not a number.
    var promptsLeft: (low: Int, high: Int)? {
        guard let session, let used = promptsUsed, used > 0, session.percent >= 2 else { return nil }
        let heaviest = Double(used) * (100 - (session.percent + 0.5)) / (session.percent + 0.5)
        let lightest = Double(used) * (100 - (session.percent - 0.5)) / (session.percent - 0.5)
        guard heaviest.isFinite, lightest.isFinite, lightest >= 0 else { return nil }
        return (Int(max(0, heaviest).rounded()), Int(max(0, lightest).rounded()))
    }

    /// The session window drives the colour; the weekly one can only raise it.
    var pressure: Pressure {
        var level = Pressure.calm
        if let session {
            if session.percent >= 95 {
                level = .critical
            } else if session.percent >= 80 {
                level = .warning
            } else if let left = session.remaining, left <= 30 * 60, session.unused >= 40 {
                level = .opportunity
            }
        }
        if let weekly {
            if weekly.percent >= 90 { level = max(level, .critical) }
            else if weekly.percent >= 80 { level = max(level, .warning) }
        }
        return level
    }
}

/// What a single poll came back with.
enum FetchResult {
    case ok(Snapshot)
    /// Usable numbers from an earlier read, because the live one failed.
    case degraded(Snapshot, note: String)
    case signedOut
    case throttled
    case failed(String)
}

enum Reading {
    case loading
    case ok(Snapshot)
    /// A previous good reading kept on screen because the latest poll failed.
    /// Reset times stay exact, so only the percentages age.
    case stale(Snapshot, since: Date, note: String)
    case signedOut
    case failed(String)

    var snapshot: Snapshot? {
        switch self {
        case .ok(let s): return s
        case .stale(let s, _, _): return s
        default: return nil
        }
    }

    var staleSince: Date? {
        if case .stale(_, let since, _) = self { return since }
        return nil
    }
}
