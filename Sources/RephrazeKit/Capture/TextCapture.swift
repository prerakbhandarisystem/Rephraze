import AppKit

/// What we found when the trigger fired.
public enum CaptureResult {
    case captured(CapturedText)
    /// Focus is on something that is not a text box -- a button, a webpage body.
    case notATextField(role: String, app: String)
    case secureField(app: String)
    case blockedApp(app: String)
    /// A real text box, but there is nothing in it.
    case empty(app: String)
    case noFocus
}

public struct CapturedText {
    public let text: String
    public let field: FocusedField
    /// True if the user had highlighted something; false if we took the whole box.
    public let wasSelection: Bool
}

/// Decides whether we may read, and then reads.
///
/// The order matters: refuse first, classify second, read last. Nothing is read
/// until we are sure we are allowed to.
public enum TextCapture {

    public static func capture() -> CaptureResult {
        guard let field = AXTextAccess.focusedField() else {
            return .noFocus
        }

        if SecureFieldGuard.isBlocked(bundleID: field.bundleID) {
            return .blockedApp(app: field.appName)
        }

        if AXTextAccess.isSecure(field) {
            return .secureField(app: field.appName)
        }

        // Chromium apps report nothing until asked. Nudge, then look again --
        // the first read after the nudge usually succeeds.
        var resolved = field
        if !AXTextAccess.isEditable(resolved) {
            ElectronAX.enableIfNeeded(pid: field.pid)
            if let retried = AXTextAccess.focusedField() {
                resolved = retried
            }
        }

        guard AXTextAccess.isEditable(resolved) else {
            return .notATextField(role: resolved.role, app: resolved.appName)
        }

        // Highlighted text wins. If nothing is highlighted, take the whole box --
        // that is the normal case when writing a message.
        if let selection = AXTextAccess.selectedText(resolved.element) {
            return .captured(CapturedText(text: selection, field: resolved, wasSelection: true))
        }

        if let whole = AXTextAccess.value(resolved.element) {
            return .captured(CapturedText(text: whole, field: resolved, wasSelection: false))
        }

        return .empty(app: resolved.appName)
    }
}
