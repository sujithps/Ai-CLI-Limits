import Foundation
import Security

/// Reads the tokens the two CLIs already wrote. Nothing here refreshes or
/// rewrites them: token rotation is the CLIs' job, and racing them would
/// invalidate a live login.
enum Credentials {

    struct Claude {
        var token: String
        var plan: String?
    }

    struct Codex {
        var token: String
        var accountID: String
    }

    static func claude() throws -> Claude {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { throw Failure.notSignedIn("Claude Code has not signed in on this Mac.") }
        guard status == errSecSuccess, let data = item as? Data else {
            // Denied, locked, or some other Keychain refusal. Saying "signed
            // out" here would send people to re-run a login that is already fine.
            throw Failure.unreadable("Keychain refused the Claude Code credentials (OSStatus \(status)).")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            throw Failure.unreadable("Keychain item has no claudeAiOauth.accessToken.")
        }
        return Claude(token: token, plan: oauth["subscriptionType"] as? String)
    }

    static func codex() throws -> Codex {
        let path = NSHomeDirectory() + "/.codex/auth.json"
        guard let data = FileManager.default.contents(atPath: path) else {
            throw Failure.notSignedIn("Codex has not signed in on this Mac.")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              let account = tokens["account_id"] as? String else {
            throw Failure.notSignedIn("~/.codex/auth.json holds no ChatGPT session.")
        }
        return Codex(token: token, accountID: account)
    }

    enum Failure: LocalizedError {
        /// No credentials exist, so signing in is the actual fix.
        case notSignedIn(String)
        /// Credentials exist but could not be read, which is a different fix.
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn(let m), .unreadable(let m): return m
            }
        }
    }
}
