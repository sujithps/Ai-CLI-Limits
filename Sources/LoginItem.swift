import Foundation
import ServiceManagement

enum LoginItem {
    static let key = "ui.startAtLogin"

    static let statusKey = "ui.startAtLoginStatus"

    /// Written by the Settings checkbox through @AppStorage.
    static var wanted: Bool { UserDefaults.standard.bool(forKey: key) }

    static var registered: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS can accept a registration and still leave it switched off pending
    /// approval in System Settings, so record what actually happened.
    static var state: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .notRegistered: return "not registered"
        case .requiresApproval: return "needs approval in System Settings, Login Items"
        case .notFound: return "app bundle not found"
        @unknown default: return "unknown"
        }
    }

    /// Returns a message on failure, nil on success.
    @discardableResult
    static func apply(_ on: Bool) -> String? {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else if registered {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Registration is tied to the bundle's code signature, so rebuilding the
    /// app silently drops it while the preference stays set. Re-assert it on
    /// every launch instead of trusting it to persist.
    static func sync() {
        var failure: String?
        if wanted, !registered { failure = apply(true) }
        UserDefaults.standard.set(failure.map { "failed: \($0)" } ?? state, forKey: statusKey)
    }
}
