import ApplicationServices

/// Accessibility permission — the one thing the whole app depends on.
///
/// macOS remembers this grant against the app's code signature. An ad-hoc
/// signed build gets a fresh identity on every rebuild, so the grant is lost
/// each time. `scripts/make-cert.sh` sets up a stable identity to avoid that.
public enum Permissions {

    /// Do we currently have Accessibility access? Never prompts.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Ask for Accessibility access, showing the system prompt if needed.
    ///
    /// The prompt only appears once per app identity. After the user has denied
    /// it, macOS silently does nothing here — which is why `openSettings()`
    /// exists as the manual route.
    @discardableResult
    public static func requestAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
