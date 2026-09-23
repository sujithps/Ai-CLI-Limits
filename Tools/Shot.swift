import AppKit
import SwiftUI

// Redraws the menu bar image used in the README from the title the app
// actually installs, so the picture cannot drift from the code.
//
// Only the menu bar is rendered here. The panel is SwiftUI, and headless there
// is no appearance to resolve .primary or .secondary against, so everything but
// the explicitly coloured text comes out white. That image is a real screenshot.

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

/// Main-thread only, so a plain box is enough to signal completion.
final class Flag { var value = false }

@main
struct Shot {
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"
        _ = NSApplication.shared
        let done = Flag()

        Task { @MainActor in
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
            let store = Store(fixed: readings)
            writeMenuBar(store.menuTitle, to: "\(out)/menubar-light.png", dark: false)
            writeMenuBar(store.menuTitle, to: "\(out)/menubar-dark.png", dark: true)
            done.value = true
        }
        // Blocking here would deadlock: the work above needs the main thread.
        while !done.value {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
