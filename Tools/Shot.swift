import AppKit
import SwiftUI

// Redraws the README images from the views the app actually installs, so the
// pictures cannot drift from the code.
//
// The figures are fixed samples, so the pictures come out the same on any
// machine and reading them needs no account or Keychain access. Pass --live to
// draw your real usage instead.
//
// The panel is SwiftUI, and headless there is no appearance to resolve
// .primary or .secondary against, so it is hosted in an unshown window whose
// appearance is set explicitly and drawn from there.

@MainActor
func writeMenuBar(_ title: NSAttributedString, to path: String, dark: Bool) {
    let pad: CGFloat = 14
    let size = title.size()
    let box = NSSize(width: (size.width + pad * 2).rounded(), height: 30)

    let image = NSImage(size: box)
    image.lockFocus()
    (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
    NSRect(origin: .zero, size: box).fill()
    NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
        title.draw(at: NSPoint(x: pad, y: ((box.height - size.height) / 2).rounded()))
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("could not encode \(path)")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

@MainActor
func writePanel(_ store: Store, to path: String, dark: Bool) {
    // The view draws no background of its own: the popover supplies one in
    // the app, so paint the same greys the menu bar image uses.
    let backdrop = Color(white: dark ? 0.13 : 0.97)
    let host = NSHostingView(rootView: Panel(store: store).background(backdrop))
    host.frame.size = host.fittingSize
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.frame.size),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.backgroundColor = .windowBackgroundColor
    window.contentView = host
    host.layoutSubtreeIfNeeded()

    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        print("could not render \(path)")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("could not encode \(path)")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

/// The numbers the README describes: a quiet Claude Code beside a Codex that
/// has nearly spent its window.
func sampleReadings() -> [Provider: Reading] {
    let now = Date()
    let hour: TimeInterval = 3600
    let day: TimeInterval = 86_400

    var claude = Snapshot()
    claude.plan = "team"
    claude.session = UsageWindow(percent: 16, resetsAt: now.addingTimeInterval(1 * hour + 31 * 60), length: 5 * hour)
    claude.weekly = UsageWindow(percent: 47, resetsAt: now.addingTimeInterval(2 * day + 5 * hour), length: 7 * day)
    claude.promptsUsed = 38

    var codex = Snapshot()
    codex.plan = "team"
    codex.session = UsageWindow(percent: 94, resetsAt: now.addingTimeInterval(1 * hour + 43 * 60), length: 5 * hour)
    codex.weekly = UsageWindow(percent: 62, resetsAt: now.addingTimeInterval(4 * day + 2 * hour), length: 7 * day)
    codex.promptsUsed = 61
    codex.models = [
        ModelStatus(name: "gpt-6-astra", available: true),
        ModelStatus(name: "gpt-6-astra-mini", available: false, availableAt: now.addingTimeInterval(3 * hour)),
    ]

    return [.claude: .ok(claude), .codex: .ok(codex)]
}

@MainActor
func liveReadings() async -> [Provider: Reading] {
    var readings: [Provider: Reading] = [:]
    for provider in Provider.allCases {
        switch await Fetch.reading(for: provider, notOlderThan: nil) {
        case .ok(let snapshot): readings[provider] = .ok(snapshot)
        case .degraded(let snapshot, let note):
            readings[provider] = .stale(snapshot, since: snapshot.fetchedAt, note: note)
        case .signedOut: readings[provider] = .signedOut
        case .throttled: readings[provider] = .failed("throttled")
        case .failed(let why): readings[provider] = .failed(why)
        }
    }
    return readings
}

/// Main-thread only, so a plain box is enough to signal completion.
final class Flag { var value = false }

@main
struct Shot {
    static func main() {
        let args = CommandLine.arguments.dropFirst()
        let live = args.contains("--live")
        let out = args.first { !$0.hasPrefix("--") } ?? "docs"
        _ = NSApplication.shared
        let done = Flag()

        Task { @MainActor in
            let store = Store(fixed: live ? await liveReadings() : sampleReadings())
            writeMenuBar(store.menuTitle, to: "\(out)/menubar-light.png", dark: false)
            writeMenuBar(store.menuTitle, to: "\(out)/menubar-dark.png", dark: true)
            // Give SwiftUI a moment to settle; the loop below keeps the run loop turning.
            try? await Task.sleep(for: .milliseconds(500))
            writePanel(store, to: "\(out)/panel-light.png", dark: false)
            writePanel(store, to: "\(out)/panel-dark.png", dark: true)
            done.value = true
        }
        // Blocking here would deadlock: the work above needs the main thread.
        while !done.value {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
