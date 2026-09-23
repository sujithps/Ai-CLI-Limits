import AppKit

// Top-level code is nonisolated, but it does run on the main thread, and the
// global keeps the delegate alive against NSApplication's weak reference.
let app = NSApplication.shared
let statusBar = MainActor.assumeIsolated { StatusBar() }
app.delegate = statusBar
app.setActivationPolicy(.accessory)
app.run()
