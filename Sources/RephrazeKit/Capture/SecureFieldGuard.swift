import Foundation

/// Refuses to read text that should never leave the machine.
///
/// Two layers. The first is the field itself: macOS marks password boxes with a
/// distinct role, and those are never read. The second is the app: some apps are
/// full of secrets even in fields that are not technically "secure", so they are
/// blocked wholesale.
///
/// This matters more than usual here, because captured text is sent to OpenAI.
public enum SecureFieldGuard {

    /// Apps where nothing should ever be captured, regardless of field type.
    public static let blockedBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.1password.1password7",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop",
        "com.dashlane.Dashlane",
        "com.lastpass.LastPass",
        "in.sinew.Enpass-Desktop",
        "com.apple.Passwords",
    ]

    public static func isBlocked(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return blockedBundleIDs.contains(bundleID)
    }
}
