import Foundation

enum Fetch {

    /// `notOlderThan` is the read time the caller already holds. A cached
    /// figure older than that is worthless, so it forces a live read instead.
    static func reading(for provider: Provider, notOlderThan held: Date?) async -> FetchResult {
        switch provider {
        case .claude: return await claude(notOlderThan: held)
        case .codex: return await codex()
        }
    }

    // MARK: Claude Code

    private static func claude(notOlderThan held: Date?) async -> FetchResult {
        let cached = claudeCache()

        // Claude Code writes every usage response it receives into
        // ~/.claude.json, and the numbers can only move while it is running.
        // Reading its cache is the same payload for no request, which matters
        // because this endpoint throttles hard and shares its budget with the
        // CLI's own polling.
        if let cached, cached.windowAlive,
           Date().timeIntervalSince(cached.snapshot.fetchedAt) < cacheTrust,
           cached.snapshot.fetchedAt >= (held ?? .distantPast) {
            return .ok(cached.snapshot)
        }

        // Only the live call needs a token, and the token is the only thing
        // that touches the Keychain, which can put a prompt in front of the
        // user. The cache path above never asks.
        let creds: Credentials.Claude
        do {
            creds = try Credentials.claude()
        } catch Credentials.Failure.notSignedIn {
            return .signedOut
        } catch {
            return .failed(error.localizedDescription)
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let live = await load(request) { root in
            var snapshot = claudeSnapshot(root, plan: creds.plan)
            snapshot.promptsUsed = countPrompts(.claude, in: snapshot)
            return snapshot
        }
        switch live {
        case .ok, .signedOut:
            return live
        default:
            guard let cached, cached.windowAlive else { return live }
            return .degraded(cached.snapshot,
                             note: "Using Claude Code's cached figure.")
        }
    }

    /// How long a cached figure is taken at face value. It stays true for as
    /// long as Claude Code is the only thing spending the quota, because the
    /// same process refreshes the cache. Two hours bounds the damage if the
    /// quota is also being spent from claude.ai or another machine.
    private static let cacheTrust: TimeInterval = 2 * 3600

    /// The `utilization` object the usage endpoint returns, and that Claude
    /// Code caches verbatim. Pure: prompt counting is the caller's job.
    static func claudeSnapshot(_ root: [String: Any], plan: String?) -> Snapshot {
        func window(_ key: String, length: TimeInterval) -> UsageWindow? {
            guard let node = root[key] as? [String: Any],
                  let percent = node["utilization"] as? Double else { return nil }
            return UsageWindow(percent: percent,
                               resetsAt: date(node["resets_at"]),
                               length: length)
        }
        var snapshot = Snapshot(session: window("five_hour", length: 5 * 3600),
                                weekly: window("seven_day", length: 7 * 86_400))
        snapshot.plan = plan
        return snapshot
    }

    /// Counted against the same window the percentage describes, and only up to
    /// the moment that percentage was read.
    private static func countPrompts(_ provider: Provider, in snapshot: Snapshot) -> Int? {
        guard let start = snapshot.session?.start else { return nil }
        return Prompts.used(by: provider, from: start, to: snapshot.fetchedAt)
    }

    /// `windowAlive` is false once the cached session window has already reset:
    /// the percentage then belongs to a window that has gone, so it is useless.
    private static func claudeCache() -> (snapshot: Snapshot, windowAlive: Bool)? {
        let path = NSHomeDirectory() + "/.claude.json"
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var cached = claudeCached(root) else { return nil }
        cached.snapshot.promptsUsed = countPrompts(.claude, in: cached.snapshot)
        return cached
    }

    /// The parts of ~/.claude.json this app reads, given the whole file parsed.
    static func claudeCached(_ root: [String: Any], now: Date = Date())
        -> (snapshot: Snapshot, windowAlive: Bool)? {
        guard let cache = root["cachedUsageUtilization"] as? [String: Any],
              let milliseconds = cache["fetchedAtMs"] as? Double,
              let utilization = cache["utilization"] as? [String: Any] else { return nil }

        // "claude_team" reads better as "team", matching what Codex reports.
        let account = root["oauthAccount"] as? [String: Any]
        let plan = (account?["organizationType"] as? String)
            .map { $0.hasPrefix("claude_") ? String($0.dropFirst(7)) : $0 }

        var snapshot = claudeSnapshot(utilization, plan: plan)
        snapshot.fetchedAt = Date(timeIntervalSince1970: milliseconds / 1000)
        let alive = snapshot.session?.resetsAt.map { $0 > now } ?? false
        return (snapshot, alive)
    }

    // MARK: Codex

    private static func codex() async -> FetchResult {
        let creds: Credentials.Codex
        do {
            creds = try Credentials.codex()
        } catch Credentials.Failure.notSignedIn {
            return .signedOut
        } catch {
            return .failed(error.localizedDescription)
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        request.setValue(creds.accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return await load(request) { root in
            var snapshot = codexSnapshot(root)
            snapshot.promptsUsed = countPrompts(.codex, in: snapshot)
            return snapshot
        }
    }

    /// The body of the wham/usage endpoint. Pure: prompt counting is the
    /// caller's job.
    static func codexSnapshot(_ root: [String: Any]) -> Snapshot {
        let limit = root["rate_limit"] as? [String: Any] ?? [:]
        func window(_ key: String, fallback: TimeInterval) -> UsageWindow? {
            guard let node = limit[key] as? [String: Any],
                  let percent = node["used_percent"] as? Double else { return nil }
            let length = (node["limit_window_seconds"] as? Double) ?? fallback
            return UsageWindow(percent: percent,
                               resetsAt: date(node["reset_at"]),
                               length: length)
        }
        var snapshot = Snapshot(session: window("primary_window", fallback: 5 * 3600),
                                weekly: window("secondary_window", fallback: 7 * 86_400))
        snapshot.plan = root["plan_type"] as? String
        if let usage = root["model_usage"] as? [String: Any] {
            snapshot.models = usage.compactMap { name, raw in
                guard let node = raw as? [String: Any] else { return nil }
                return ModelStatus(name: name,
                                   available: (node["available"] as? Bool) ?? false,
                                   availableAt: date(node["available_at"]))
            }.sorted { $0.name < $1.name }
        }
        return snapshot
    }

    // MARK: Plumbing

    private static func load(_ request: URLRequest,
                             parse: ([String: Any]) -> Snapshot?) async -> FetchResult {
        var request = request
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { return .signedOut }
            if code == 429 { return .throttled }
            guard code == 200 else { return .failed("HTTP \(code)") }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let snapshot = parse(root) else { return .failed("unexpected response shape") }
            return .ok(snapshot)
        } catch {
            return .failed((error as NSError).localizedDescription)
        }
    }

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Claude sends ISO timestamps with microsecond precision, Codex sends unix
    /// seconds. ISO8601DateFormatter rejects more than three fractional digits,
    /// so trim before handing it over.
    static func date(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSince1970: Double(seconds)) }
        guard var text = value as? String else { return nil }
        if let dot = text.firstIndex(of: ".") {
            var cursor = text.index(after: dot)
            var digits = 0
            while cursor < text.endIndex, text[cursor].isNumber {
                digits += 1
                cursor = text.index(after: cursor)
            }
            if digits > 3 {
                text.removeSubrange(text.index(dot, offsetBy: 4)..<cursor)
            }
        }
        return withFraction.date(from: text) ?? plain.date(from: text)
    }
}
