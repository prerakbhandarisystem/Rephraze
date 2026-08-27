import ApplicationServices

/// Wakes up accessibility in Chromium-based apps.
///
/// Slack, Discord, Teams, Notion and VS Code are all websites in a costume.
/// Chromium keeps its accessibility tree switched *off* until an assistive tool
/// asks for it, because building that tree costs performance. Setting
/// `AXManualAccessibility` on the application element is the documented signal
/// that says "I am an assistive tool, please switch it on".
///
/// Without this, those apps report nothing at all and every capture would have
/// to fall back to the clipboard.
public enum ElectronAX {

    private static var nudged: Set<pid_t> = []

    /// Ask an app to start describing itself. Cheap and harmless on apps that
    /// do not need it -- they simply reject the attribute.
    ///
    /// Only sent once per app per launch; the setting sticks.
    public static func enableIfNeeded(pid: pid_t) {
        guard !nudged.contains(pid) else { return }
        nudged.insert(pid)

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(
            app, "AXManualAccessibility" as CFString, kCFBooleanTrue
        )
        // Older Electron builds respond to this one instead.
        AXUIElementSetAttributeValue(
            app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue
        )
    }

    /// Forget a quit app, so a relaunched one gets nudged again.
    public static func forget(pid: pid_t) {
        nudged.remove(pid)
    }
}
