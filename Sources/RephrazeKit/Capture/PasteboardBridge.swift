import AppKit

/// Borrows the clipboard, and always gives it back.
///
/// Some apps will not hand over their text through the Accessibility API, and
/// some will not accept text that way either. For those we synthesise ⌘C / ⌘V,
/// which means briefly using the user's clipboard. Silently destroying whatever
/// they had copied would be unacceptable, so every borrow is paired with a
/// restore.
public enum PasteboardBridge {

    /// Everything that was on the clipboard, so it can be put back exactly.
    public struct Snapshot {
        let items: [[String: Data]]
        let changeCount: Int
    }

    private static let vKeyCode: CGKeyCode = 9

    // MARK: - Save and restore

    public static func snapshot() -> Snapshot {
        let pasteboard = NSPasteboard.general
        var saved: [[String: Data]] = []

        for item in pasteboard.pasteboardItems ?? [] {
            var typed: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    typed[type.rawValue] = data
                }
            }
            if !typed.isEmpty { saved.append(typed) }
        }

        return Snapshot(items: saved, changeCount: pasteboard.changeCount)
    }

    public static func restore(_ snapshot: Snapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard !snapshot.items.isEmpty else { return }

        let items: [NSPasteboardItem] = snapshot.items.map { stored in
            let item = NSPasteboardItem()
            for (type, data) in stored {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    public static func setString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public static var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    public static func string() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    // MARK: - Synthetic keystrokes

    public static func sendPaste() { send(keyCode: vKeyCode) }

    private static func send(keyCode: CGKeyCode) {
        // .combinedSessionState so the synthesised event carries the same
        // context as a real keypress.
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
