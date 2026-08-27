import AppKit
import ApplicationServices

/// Puts the chosen rewrite back into the box it came from.
///
/// ## Why writing is not symmetric with reading
/// Reading works the same everywhere. Writing does not, and getting it wrong
/// loses the user's text silently — the worst kind of bug.
///
/// - **Native apps** take text through the Accessibility API cleanly, and it
///   usually lands on their undo stack.
/// - **Browsers and Electron apps** keep their own model of the field's value
///   in JavaScript. A value that appears without an `input` event gets reverted
///   on the next render, or the old text gets submitted. So those need a real
///   paste, which the page observes like any human paste.
public enum TextWriter {

    /// Apps whose text fields are really web views.
    private static let webHostBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",   // Arc
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.tinyspeck.slackmacgap",    // Slack
        "com.hnc.Discord",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "notion.id",
        "com.electron.notion",
        "com.microsoft.VSCode",
        "com.figma.Desktop",
        "com.linear",
        "com.spotify.client",
    ]

    public enum WriteResult {
        case wroteViaAccessibility
        case wroteViaPaste
        case failed(String)
    }

    /// Replace the field's contents (or its selection) with `text`.
    public static func write(
        _ text: String,
        to field: FocusedField,
        replacingSelection: Bool
    ) -> WriteResult {

        let isWebHost = field.bundleID.map(webHostBundleIDs.contains) ?? false

        // Web hosts go straight to paste. Trying Accessibility first would often
        // appear to work and then silently revert.
        if !isWebHost {
            if writeViaAccessibility(text, to: field, replacingSelection: replacingSelection) {
                return .wroteViaAccessibility
            }
        }

        if writeViaPaste(text, to: field, replacingSelection: replacingSelection) {
            return .wroteViaPaste
        }

        return .failed("Could not write to \(field.appName)")
    }

    // MARK: - Accessibility

    private static func writeViaAccessibility(
        _ text: String,
        to field: FocusedField,
        replacingSelection: Bool
    ) -> Bool {

        let attribute = replacingSelection
            ? kAXSelectedTextAttribute as CFString
            : kAXValueAttribute as CFString

        let status = AXUIElementSetAttributeValue(field.element, attribute, text as CFTypeRef)
        guard status == .success else { return false }

        // Trust nothing: read it back. Some apps accept the write and ignore it.
        if replacingSelection {
            // The selection is gone after replacing it, so check the whole value
            // now contains what we wrote.
            guard let value = AXTextAccess.value(field.element) else { return false }
            return value.contains(text)
        } else {
            guard let value = AXTextAccess.value(field.element) else { return false }
            return value == text
        }
    }

    // MARK: - Paste

    private static func writeViaPaste(
        _ text: String,
        to field: FocusedField,
        replacingSelection: Bool
    ) -> Bool {

        let saved = PasteboardBridge.snapshot()

        // If we are replacing the whole field, select it first so the paste
        // overwrites rather than appends.
        if !replacingSelection {
            selectAll(in: field)
        }

        PasteboardBridge.setString(text)
        PasteboardBridge.sendPaste()

        // Give the target app a moment to consume the paste before we take the
        // clipboard back, otherwise we restore it out from under them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            PasteboardBridge.restore(saved)
        }

        return true
    }

    /// Select the whole field through Accessibility, which is safer than
    /// synthesising ⌘A — in a browser ⌘A can select the entire page.
    private static func selectAll(in field: FocusedField) {
        guard let current = AXTextAccess.value(field.element) else { return }
        var range = CFRange(location: 0, length: current.utf16.count)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(
            field.element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
    }
}
