import AppKit
import Combine
import SwiftUI

/// The menu bar item is AppKit rather than a SwiftUI MenuBarExtra: only an
/// NSAttributedString title reliably keeps its own colours up there.
@MainActor
final class StatusBar: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let popover = NSPopover()
    private var item: NSStatusItem!
    private var watch: AnyCancellable?

    func applicationDidFinishLaunching(_ note: Notification) {
        Notifier.shared.requestAccess()
        LoginItem.sync()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.setAccessibilityLabel("Claude Code and Codex usage")

        popover.behavior = .transient

        watch = store.$menuTitle.sink { [weak self] title in
            self?.item.button?.attributedTitle = title
        }
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Rebuilt on every open: a hidden SwiftUI view stops tracking the
        // store, and reusing it showed countdowns minutes behind the menu bar.
        popover.contentViewController = NSHostingController(rootView: Panel(store: store))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await store.refreshIfStale() }
    }
}
