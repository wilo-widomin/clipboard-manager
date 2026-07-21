//
//  Authenticator.swift
//  ClipboardManager
//
//  Gates sensitive actions (currently: editing an item's detail note) behind
//  the macOS user's own credentials. We don't store or manage any password
//  ourselves — LocalAuthentication shows the native system prompt (Touch ID
//  with a fallback to the login password), so the protection is tied to
//  whoever is signed in. A successful auth is cached for a short window so the
//  user isn't re-prompted while editing several items in a row.
//

import Foundation
import LocalAuthentication

@MainActor
final class Authenticator {

    static let shared = Authenticator()

    /// How long a successful authentication stays valid before we prompt again.
    private let cacheWindow: TimeInterval = 5 * 60

    /// Timestamp of the last successful authentication (nil = never / expired).
    private var lastSuccess: Date?

    private init() {}

    /// True while a recent authentication is still within the cache window.
    private var isCachedValid: Bool {
        guard let last = lastSuccess else { return false }
        return Date().timeIntervalSince(last) < cacheWindow
    }

    /// Authenticates the current macOS user. Invokes `completion(true)` right
    /// away if a recent auth is still cached; otherwise presents the native
    /// system prompt and reports the result on the main queue.
    ///
    /// - Parameters:
    ///   - reason: Localised sentence shown in the system dialog.
    ///   - completion: Called with `true` on success, `false` on failure/cancel.
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        if isCachedValid {
            completion(true)
            return
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"

        // `.deviceOwnerAuthentication` = biometrics (Touch ID) when available,
        // with an automatic fallback to the account password. That's the
        // "user's password" the feature is meant to require.
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            NSLog("ClipboardManager: authentication unavailable: \(policyError?.localizedDescription ?? "unknown")")
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            // The reply lands on a private queue; hop back to the main actor to
            // touch `lastSuccess` and run the UI-facing completion.
            Task { @MainActor in
                if success { self.lastSuccess = Date() }
                completion(success)
            }
        }
    }
}
