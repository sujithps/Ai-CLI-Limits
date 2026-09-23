import Foundation
import UserNotifications

/// What the last poll saw, so a change can be told apart from a repeat.
/// Persisted so a restart does not replay every alert.
private struct Memory: Codable {
    var sessionResetsAt: Double?
    var sessionPercent: Double = 0
    var sessionFired: [Int] = []
    var closingFired = false
    var weeklyResetsAt: Double?
    var weeklyFired: [Int] = []
    var models: [String: Bool] = [:]
}

enum Alerts {
    static let reset = "notify.reset"
    static let threshold = "notify.threshold"
    static let closing = "notify.closing"
    static let weekly = "notify.weekly"
    static let models = "notify.models"

    static let defaults: [String: Any] = [
        reset: true, threshold: true, closing: true, weekly: true, models: true,
    ]
}

@MainActor
final class Notifier {
    static let shared = Notifier()

    private let sessionSteps = [50, 80, 95, 100]
    private let weeklySteps = [75, 90, 100]
    /// How close to the reset the "you still have room" nudge fires, and how
    /// much unused quota makes it worth saying.
    private let closingLead: TimeInterval = 30 * 60
    private let closingUnused: Double = 40

    func requestAccess() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Whether macOS will actually show what we post, for the settings panel.
    static func authorized() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .authorized
    }

    func evaluate(_ snapshot: Snapshot, for provider: Provider) {
        var memory = load(provider)
        let first = memory.sessionResetsAt == nil && memory.weeklyResetsAt == nil

        if let session = snapshot.session {
            if rolled(session.resetsAt, was: memory.sessionResetsAt) {
                if !first, memory.sessionPercent >= 25, on(Alerts.reset) {
                    post(title: "\(provider.title) · 5h window reset",
                         body: resetBody(session))
                }
                memory.sessionFired = []
                memory.closingFired = false
            }
            memory.sessionResetsAt = session.resetsAt?.timeIntervalSince1970
            memory.sessionPercent = session.percent

            for step in sessionSteps where session.percent >= Double(step) {
                guard !memory.sessionFired.contains(step) else { continue }
                memory.sessionFired.append(step)
                guard !first, on(Alerts.threshold) else { continue }
                post(title: step >= 100
                        ? "\(provider.title) · 5h limit reached"
                        : "\(provider.title) · \(step)% of the 5h window used",
                     body: resetBody(session))
            }

            if !first, on(Alerts.closing), !memory.closingFired,
               let left = session.remaining, left > 0, left <= closingLead,
               session.unused >= closingUnused {
                memory.closingFired = true
                post(title: "\(provider.title) · 5h window ends in \(Fmt.span(left))",
                     body: "\(Fmt.percent(session.unused)) of it is still unused.")
            }
        }

        if let weekly = snapshot.weekly {
            if rolled(weekly.resetsAt, was: memory.weeklyResetsAt) { memory.weeklyFired = [] }
            memory.weeklyResetsAt = weekly.resetsAt?.timeIntervalSince1970
            for step in weeklySteps where weekly.percent >= Double(step) {
                guard !memory.weeklyFired.contains(step) else { continue }
                memory.weeklyFired.append(step)
                guard !first, on(Alerts.weekly) else { continue }
                post(title: step >= 100
                        ? "\(provider.title) · weekly limit reached"
                        : "\(provider.title) · \(step)% of the weekly limit used",
                     body: weekly.resetsAt.map { "Resets \(Fmt.moment($0))." } ?? "")
            }
        }

        for model in snapshot.models {
            let before = memory.models[model.name]
            memory.models[model.name] = model.available
            guard !first, let before, before != model.available, on(Alerts.models) else { continue }
            if model.available {
                post(title: "\(provider.title) · \(model.name) available", body: "It can be used again.")
            } else {
                let when = model.availableAt.map { "Back \(Fmt.moment($0))." } ?? "No return time given."
                post(title: "\(provider.title) · \(model.name) unavailable", body: when)
            }
        }

        save(memory, for: provider)
    }

    private func resetBody(_ window: UsageWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "" }
        return "Resets in \(Fmt.span(resetsAt.timeIntervalSinceNow)) (\(Fmt.moment(resetsAt)))."
    }

    /// A reset instant that jumped forward means a new window, not a new reading.
    private func rolled(_ now: Date?, was: Double?) -> Bool {
        guard let now else { return false }
        guard let was else { return true }
        return now.timeIntervalSince1970 > was + 60
    }

    private func on(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func key(_ provider: Provider) -> String { "memory.\(provider.rawValue)" }

    private func load(_ provider: Provider) -> Memory {
        guard let data = UserDefaults.standard.data(forKey: key(provider)),
              let memory = try? JSONDecoder().decode(Memory.self, from: data) else { return Memory() }
        return memory
    }

    private func save(_ memory: Memory, for provider: Provider) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: key(provider))
    }
}
