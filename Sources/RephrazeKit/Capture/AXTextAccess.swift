import AppKit
import ApplicationServices

/// A text box that currently has keyboard focus.
public struct FocusedField {
    public let element: AXUIElement
    public let role: String
    public let subrole: String?
    public let pid: pid_t
    public let bundleID: String?

    public var appName: String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? "unknown"
    }
}

/// Reading and writing text through the Accessibility API — the same machinery
/// screen readers use. This is the clean path: nothing is copied, the clipboard
/// is never touched, and most native Mac apps answer honestly.
public enum AXTextAccess {

    /// Roles that mean "you can type here".
    ///
    /// Web fields report these too: an `<input>` comes through as AXTextField
    /// and a `<textarea>` as AXTextArea. Chat composers built on contenteditable
    /// usually surface as AXTextArea once the app is describing itself.
    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
    ]

    /// Password boxes. Never read these, ever.
    private static let secureSubroles: Set<String> = [
        kAXSecureTextFieldSubrole as String,
    ]

    // MARK: - Finding focus

    /// What has keyboard focus right now, anywhere on the system.
    public static func focusedField() -> FocusedField? {
        let systemWide = AXUIElementCreateSystemWide()

        guard let element: AXUIElement = copyAttribute(systemWide, kAXFocusedUIElementAttribute)
        else {
            return nil
        }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        let role: String = copyAttribute(element, kAXRoleAttribute) ?? ""
        let subrole: String? = copyAttribute(element, kAXSubroleAttribute)

        return FocusedField(
            element: element,
            role: role,
            subrole: subrole,
            pid: pid,
            bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        )
    }

    // MARK: - Classifying

    /// Is this something you can type into?
    ///
    /// Deliberately strict. If we cannot confirm it is a text box we do nothing,
    /// because the alternative -- guessing -- risks replacing something that was
    /// never meant to be touched.
    public static func isEditable(_ field: FocusedField) -> Bool {
        if editableRoles.contains(field.role) { return true }

        // Some web and Electron views report a generic role but still expose an
        // editable text value. Accept those only when they actually answer.
        if field.role == (kAXGroupRole as String) || field.role == "AXWebArea" {
            return value(field.element) != nil
        }

        return false
    }

    /// Is this a password box?
    public static func isSecure(_ field: FocusedField) -> Bool {
        if let subrole = field.subrole, secureSubroles.contains(subrole) { return true }
        // Some apps report the secure role without a subrole.
        return field.role == "AXSecureTextField"
    }

    // MARK: - Reading

    /// The highlighted text, if any.
    public static func selectedText(_ element: AXUIElement) -> String? {
        let text: String? = copyAttribute(element, kAXSelectedTextAttribute)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// Everything in the box.
    public static func value(_ element: AXUIElement) -> String? {
        let text: String? = copyAttribute(element, kAXValueAttribute)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Plumbing

    /// Typed wrapper around AXUIElementCopyAttributeValue, which is untyped C.
    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        guard status == .success, let raw else { return nil }
        return raw as? T
    }
}
