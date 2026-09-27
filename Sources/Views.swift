import SwiftUI

struct Panel: View {
    @ObservedObject var store: Store
    @State private var showSettings = false

    /// The popover cannot scroll itself, so tall content gets pushed off the
    /// top of the screen. Cap it against the usable screen instead.
    private var ceiling: CGFloat {
        let usable = NSScreen.main?.visibleFrame.height ?? 800
        return min(620, max(320, usable - 90))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Provider.allCases.enumerated()), id: \.element) { index, provider in
                    if index > 0 {
                        Divider().padding(.vertical, 12)
                    }
                    ProviderBlock(provider: provider,
                                  reading: store.readings[provider] ?? .loading,
                                  retryAt: store.retryTime(for: provider))
                }

                Divider().padding(.vertical, 12)
                Footer(store: store, showSettings: $showSettings)

                if showSettings {
                    Settings().padding(.top, 12)
                }
            }
            .padding(14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 304)
        .frame(maxHeight: ceiling)
        .task { await store.refreshIfStale() }
    }
}

private struct ProviderBlock: View {
    let provider: Provider
    let reading: Reading
    let retryAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if let plan = reading.snapshot?.plan {
                    Text(plan).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }

            switch reading {
            case .loading:
                Text("Checking…").font(.system(size: 11)).foregroundStyle(.secondary)

            case .signedOut:
                Text(provider == .claude
                     ? "Not signed in. Run claude in a terminal and sign in."
                     : "Not signed in. Run codex login in a terminal.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .failed(let why):
                Text("Could not read usage: \(why)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .ok(let snapshot):
                windows(snapshot)
                if Date().timeIntervalSince(snapshot.fetchedAt) > 120 {
                    Text("Read at \(Fmt.clock.string(from: snapshot.fetchedAt)).")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }

            case .stale(let snapshot, let since, let note):
                windows(snapshot)
                Text(retryAt.map { "\(note) Read \(Fmt.clock.string(from: since)), retrying \(Fmt.moment($0))." }
                     ?? "\(note) Read \(Fmt.clock.string(from: since)).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func windows(_ snapshot: Snapshot) -> some View {
        if let session = snapshot.session {
            WindowRow(label: "5h session", window: session, showPace: true)
            if let used = snapshot.promptsUsed, let left = snapshot.promptsLeft {
                let lo = Fmt.coarse(left.low), hi = Fmt.coarse(left.high)
                let estimate = lo == hi ? "about \(lo) left" : "about \(lo)-\(hi) left"
                Text("\(used) prompt\(used == 1 ? "" : "s") spent \(Fmt.percent(session.percent)) · \(estimate)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let weekly = snapshot.weekly {
            WindowRow(label: "This week", window: weekly, showPace: true)
        }
        ForEach(snapshot.models) { model in
            ModelRow(model: model)
        }
    }
}

private struct WindowRow: View {
    let label: String
    let window: UsageWindow
    let showPace: Bool

    private var elapsedFraction: Double? {
        guard let start = window.start, window.length > 0 else { return nil }
        return min(max(Date().timeIntervalSince(start) / window.length, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(Fmt.percent(window.percent))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Fmt.tint(window.percent))
            }

            Meter(percent: window.percent, pace: showPace ? elapsedFraction : nil)

            if let resetsAt = window.resetsAt {
                Text("Resets in \(Fmt.span(resetsAt.timeIntervalSinceNow)) · \(Fmt.moment(resetsAt))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            if showPace, let burnout = window.burnout {
                Text("At this pace it runs out around \(Fmt.moment(burnout)).")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if showPace, window.length <= 6 * 3600,
                      let left = window.remaining, left <= 45 * 60, window.unused >= 25 {
                Text("\(Fmt.percent(window.unused)) unused with \(Fmt.span(left)) left.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Usage as a fill, time as a tick. Fill behind the tick means the window is
/// burning slower than the clock; fill past it means the opposite.
private struct Meter: View {
    let percent: Double
    let pace: Double?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(Fmt.tint(percent))
                    .frame(width: max(2, width * min(percent, 100) / 100))
                if let pace, pace > 0.015, pace < 0.99 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 1.5)
                        .offset(x: min(width * pace, width - 1.5))
                }
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("\(Fmt.percent(percent)) used")
    }
}

private struct ModelRow: View {
    let model: ModelStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(model.name).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if model.available {
                Text("available").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let back = model.availableAt {
                Text("back \(Fmt.moment(back))").font(.system(size: 11)).foregroundStyle(.orange)
            } else {
                Text("unavailable").font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
    }
}

private struct Footer: View {
    @ObservedObject var store: Store
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button("Refresh") { Task { await store.poll(force: true) } }
                Button(showSettings ? "Done" : "Settings") { showSettings.toggle() }
                Spacer(minLength: 4)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.accessoryBar)

            if let lastPoll = store.lastPoll {
                Text("Polled \(Fmt.clock.string(from: lastPoll))")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11))
    }
}

private struct Settings: View {
    @AppStorage("ui.compact") private var compact = false
    @AppStorage(Alerts.reset) private var notifyReset = true
    @AppStorage(Alerts.threshold) private var notifyThreshold = true
    @AppStorage(Alerts.closing) private var notifyClosing = true
    @AppStorage(Alerts.weekly) private var notifyWeekly = true
    @AppStorage(Alerts.models) private var notifyModels = true
    @AppStorage(LoginItem.key) private var atLogin = false
    @State private var loginError: String?
    @State private var notificationsAllowed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Notify me when").font(.system(size: 11, weight: .semibold))
            if !notificationsAllowed {
                Text("Notifications are turned off for AI CLI Limits in System Settings.")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("A 5h window resets", isOn: $notifyReset)
            Toggle("A 5h window passes 50, 80 or 95%", isOn: $notifyThreshold)
            Toggle("A 5h window is closing with room left", isOn: $notifyClosing)
            Toggle("The weekly limit passes 75 or 90%", isOn: $notifyWeekly)
            Toggle("A model's availability changes", isOn: $notifyModels)

            Divider().padding(.vertical, 4)
            Toggle("Show percentages only in the menu bar", isOn: $compact)
            Toggle("Start at login", isOn: $atLogin)
                .onChange(of: atLogin) { _, wanted in
                    loginError = LoginItem.apply(wanted)
                    if loginError != nil { atLogin = LoginItem.registered }
                    else if wanted, !LoginItem.registered { loginError = LoginItem.state }
                }
            if let loginError {
                Text(loginError).font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 11))
        .toggleStyle(.checkbox)
        .task { notificationsAllowed = await Notifier.authorized() }
    }
}
