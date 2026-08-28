import AppKit
import UserNotifications

/// The two ways the app is allowed to speak up when you are not looking at it.
///
/// ## Everything here is off until asked for
/// The panel appears next to your caret, which is where your eyes already are,
/// so a sound on every rewrite would be a sound dozens of times a day telling
/// you something you can see. These exist for the cases where the panel is not
/// where you are looking: a rewrite that failed while you carried on typing
/// somewhere else, and an allowance that ran out.
///
/// ## Nothing here may crash a bare binary
/// `UNUserNotificationCenter.current()` raises, rather than failing, when the
/// process has no bundle -- which is exactly what `swift run` produces. Every
/// path through this file checks for a bundle first.
public enum Feedback {

    // MARK: - Sound

    /// System sounds, not shipped ones. They are already familiar, they already
    /// respect the user's alert volume, and they are the tones every other app
    /// uses for the same two meanings.
    private static let readyTone = "Tink"
    private static let failureTone = "Basso"

    /// The first rewrite has arrived on screen.
    public static func rewriteReady() {
        guard Settings.soundOnReady else { return }
        play(readyTone)
    }

    /// A rewrite did not come back.
    public static func rewriteFailed() {
        guard Settings.soundOnFailure else { return }
        play(failureTone)
    }

    private static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Notifications

    /// True when notifications can be delivered at all in this build.
    public static var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Ask macOS for permission, and report whether it was given.
    ///
    /// Called when a notification switch is turned on rather than at launch. An
    /// app that asks for notification access before it has anything to notify
    /// you about gets refused, and the refusal is permanent until someone digs
    /// through System Settings to undo it.
    public static func requestNotificationAccess() async -> Bool {
        guard notificationsAvailable else { return false }
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.app.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// A rewrite failed while you were elsewhere.
    ///
    /// The message is deliberately vague about the text. A notification banner
    /// is shown on a shared screen, on a locked screen, and in Notification
    /// Centre afterwards -- none of which are places to put a sentence someone
    /// was writing.
    public static func notifyRewriteFailed(_ reason: String) {
        guard Settings.notifyOnFailure else { return }
        post(
            identifier: "rewrite-failed",
            title: "That rewrite did not come back",
            body: reason
        )
    }

    /// The free rewrites are nearly gone.
    ///
    /// Sent once per remaining count, so the number falling from five to four
    /// is one notification rather than one per rewrite at every count below the
    /// mark. The identifier carries the count, which is what makes that true.
    public static func notifyRunningLow(remaining: Int) {
        guard Settings.notifyWhenLow else { return }
        post(
            identifier: "allowance-\(remaining)",
            title: remaining == 0
                ? "Your \(UsageQuota.allowance) rewrites are used"
                : "\(remaining) rewrites left",
            body: "Nothing stops working — the count is there so it is not a surprise."
        )
    }

    private static func post(identifier: String, title: String, body: String) {
        guard notificationsAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            // nil means "now". A trigger would schedule it.
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("Notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
