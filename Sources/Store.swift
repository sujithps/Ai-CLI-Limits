import AppKit
import Combine
import Foundation

@MainActor
final class Store: ObservableObject {
    @Published private(set) var readings: [Provider: Reading] = [
        .claude: .loading, .codex: .loading,
    ]
    @Published private(set) var lastPoll: Date?
    @Published private(set) var menuTitle = NSAttributedString()
    /// Drives the countdowns without a new network call.
    @Published private var tick = Date()

    /// The Claude usage endpoint throttles on a budget shared with Claude
    /// Code's own polling, and a 429 there took over 15 minutes to clear even
    /// with no other traffic. Six reads an hour leaves that budget alone, and
    /// costs nothing that matters: 10 minutes is 3% of a 5-hour window, and the
    /// countdowns are computed locally so they stay exact between polls.
    private let pollEvery: TimeInterval = 600
    private let throttleBackoff: TimeInterval = 600
    private let errorBackoff: TimeInterval = 60
    private let maxBackoff: TimeInterval = 1800

    private var lastGood: [Provider: (snapshot: Snapshot, at: Date)] = [:]
    private var failures: [Provider: Int] = [:]
    private var nextAllowed: [Provider: Date] = [:]

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var polling = false
    /// Holds fixed readings and never polls, so the menu bar title can be
    /// rendered for the README without a live account.
    private let fixed: Bool

    init(fixed readings: [Provider: Reading]) {
        self.fixed = true
        self.readings = readings
        self.lastPoll = Date()
        self.menuTitle = NSAttributedString()
        self.menuTitle = buildTitle()
    }

    init() {
        self.fixed = false
        UserDefaults.standard.register(defaults: Alerts.defaults)
        restore()
        pollTimer = .scheduledTimer(withTimeInterval: pollEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        tickTimer = .scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tick = Date()
                self.menuTitle = self.buildTitle()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        Task { await poll() }
    }

    /// Called when the panel opens. The countdowns are computed locally, so an
    /// open does not need a fresh percentage.
    func refreshIfStale(olderThan age: TimeInterval = 120) async {
        if fixed { return }
        if let lastPoll, Date().timeIntervalSince(lastPoll) < age { return }
        await poll()
    }

    /// `force` is the Refresh button: it ignores the per-provider backoff.
    func poll(force: Bool = false) async {
        guard !fixed, !polling else { return }
        polling = true
        defer { polling = false }

        let now = Date()
        let due = Provider.allCases.filter { force || (nextAllowed[$0] ?? .distantPast) <= now }
        guard !due.isEmpty else { return }

        let fetched = await withTaskGroup(of: (Provider, FetchResult).self) { group in
            for provider in due {
                let held = lastGood[provider]?.at
                group.addTask { (provider, await Fetch.reading(for: provider, notOlderThan: held)) }
            }
            var out: [Provider: FetchResult] = [:]
            for await (provider, result) in group { out[provider] = result }
            return out
        }

        for (provider, result) in fetched { apply(result, to: provider) }
        lastPoll = Date()
        tick = Date()
        menuTitle = buildTitle()
    }

    private func apply(_ result: FetchResult, to provider: Provider) {
        switch result {
        case .ok(let snapshot):
            let (best, isNewer) = newest(snapshot, for: provider)
            if isNewer {
                remember(best, for: provider)
                Notifier.shared.evaluate(best, for: provider)
            }
            failures[provider] = 0
            nextAllowed[provider] = nil
            readings[provider] = .ok(best)

        case .degraded(let snapshot, let note):
            // Real numbers, just older, so keep them. No notifications: this is
            // not new information, only a failed attempt to get newer.
            let (best, isNewer) = newest(snapshot, for: provider)
            if isNewer { remember(best, for: provider) }
            readings[provider] = .stale(best, since: best.fetchedAt, note: note)
            backOff(provider, base: throttleBackoff)

        case .signedOut:
            lastGood[provider] = nil
            failures[provider] = 0
            nextAllowed[provider] = nil
            readings[provider] = .signedOut

        case .throttled:
            backOff(provider, base: throttleBackoff)
            fallBack(provider,
                     note: "Usage endpoint is throttling this app.",
                     hard: "The usage endpoint is throttling this app (HTTP 429).")

        case .failed(let why):
            backOff(provider, base: errorBackoff)
            fallBack(provider, note: why, hard: "Could not read usage: \(why)")
        }
    }

    /// Never move a provider backwards in time. A cached figure can be older
    /// than a live read this app already made.
    private func newest(_ candidate: Snapshot, for provider: Provider) -> (Snapshot, Bool) {
        if let good = lastGood[provider], good.at > candidate.fetchedAt { return (good.snapshot, false) }
        return (candidate, true)
    }

    private func remember(_ snapshot: Snapshot, for provider: Provider) {
        lastGood[provider] = (snapshot, snapshot.fetchedAt)
        persist(snapshot, for: provider, at: snapshot.fetchedAt)
    }

    private func backOff(_ provider: Provider, base: TimeInterval) {
        let streak = (failures[provider] ?? 0) + 1
        failures[provider] = streak
        nextAllowed[provider] = Date()
            .addingTimeInterval(min(maxBackoff, base * pow(2, Double(streak - 1))))
    }

    /// Hold on to the last good numbers rather than replacing them with an error.
    private func fallBack(_ provider: Provider, note: String, hard: String) {
        if let good = lastGood[provider] {
            readings[provider] = .stale(good.snapshot, since: good.at, note: note)
        } else {
            readings[provider] = .failed(hard)
        }
    }

    // MARK: Keeping the last good reading across restarts

    private struct Kept: Codable {
        var snapshot: Snapshot
        var at: Date
    }

    private func keptKey(_ provider: Provider) -> String { "lastGood.\(provider.rawValue)" }

    private func persist(_ snapshot: Snapshot, for provider: Provider, at: Date) {
        guard let data = try? JSONEncoder().encode(Kept(snapshot: snapshot, at: at)) else { return }
        UserDefaults.standard.set(data, forKey: keptKey(provider))
    }

    /// Restoring only makes sense while the session window it describes is
    /// still open; past that the percentage belongs to a window that has gone.
    private func restore() {
        for provider in Provider.allCases {
            guard let data = UserDefaults.standard.data(forKey: keptKey(provider)),
                  let kept = try? JSONDecoder().decode(Kept.self, from: data),
                  let resetsAt = kept.snapshot.session?.resetsAt,
                  resetsAt > Date() else { continue }
            lastGood[provider] = (kept.snapshot, kept.at)
            readings[provider] = .stale(kept.snapshot, since: kept.at,
                                        note: "Not read since this app last ran.")
        }
        menuTitle = buildTitle()
    }

    /// When the app will next try a provider again, for the panel to show.
    func retryTime(for provider: Provider) -> Date? { nextAllowed[provider] }

    /// Each provider is coloured on its own, so a red Claude chunk sits next to
    /// a calm Codex one instead of dyeing the whole title.
    private func buildTitle() -> NSAttributedString {
        let compact = UserDefaults.standard.bool(forKey: "ui.compact")
        let title = NSMutableAttributedString()

        for provider in Provider.allCases {
            if title.length > 0 {
                title.append(NSAttributedString(string: "  ", attributes: [.font: Fmt.menuFont]))
            }
            let reading = readings[provider] ?? .loading
            let text: String
            var pressure = Pressure.calm

            switch reading {
            case .loading:
                text = "\(provider.badge) ·"
            case .signedOut:
                text = "\(provider.badge) –"
            case .failed:
                text = "\(provider.badge) ?"
            case .ok(let snapshot), .stale(let snapshot, _, _):
                pressure = snapshot.pressure
                if let session = snapshot.session {
                    let used = Fmt.percent(session.percent)
                    if !compact, let left = session.remaining {
                        text = "\(provider.badge) \(used)·\(Fmt.span(left, tight: true))"
                    } else {
                        text = "\(provider.badge) \(used)"
                    }
                } else {
                    text = "\(provider.badge) –"
                }
            }

            // Numbers older than a quarter hour get dimmed, unless they are
            // already saying something urgent.
            var color = Fmt.menuColor(pressure)
            if pressure == .calm, let since = reading.staleSince,
               Date().timeIntervalSince(since) > 15 * 60 {
                color = .secondaryLabelColor
            }

            title.append(NSAttributedString(string: text, attributes: [
                .font: Fmt.menuFont,
                .foregroundColor: color,
            ]))
        }
        return title
    }
}
