import AppKit

/// Where the API key and preferences live.
public final class SettingsWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var keyField: NSSecureTextField?
    private var modelField: NSTextField?
    private var historyToggle: NSButton?
    private var statusLabel: NSTextField?

    public var history: HistoryStore?

    public override init() {
        super.init()
    }

    public func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.setActivationPolicy(.regular)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Rephraze Settings"
        win.center()
        win.delegate = self
        win.isReleasedWhenClosed = false
        win.contentView = buildContent()

        window = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        loadCurrentValues()
    }

    // MARK: - Layout

    private func buildContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        let left: CGFloat = 28
        let width: CGFloat = 464

        var y: CGFloat = 310

        root.addSubview(heading("OpenAI API key", at: NSRect(x: left, y: y, width: width, height: 20)))
        y -= 26

        let key = NSSecureTextField(frame: NSRect(x: left, y: y, width: width, height: 24))
        key.placeholderString = "sk-…"
        root.addSubview(key)
        keyField = key
        y -= 22

        root.addSubview(caption(
            "Stored in your macOS Keychain — never in a file, a log, or the app itself.",
            at: NSRect(x: left, y: y, width: width, height: 18)
        ))
        y -= 38

        root.addSubview(heading("Model", at: NSRect(x: left, y: y, width: width, height: 20)))
        y -= 26

        let model = NSTextField(frame: NSRect(x: left, y: y, width: 240, height: 24))
        model.placeholderString = Settings.defaultModel
        root.addSubview(model)
        modelField = model
        y -= 22

        root.addSubview(caption(
            "A small fast model keeps rewrites under a second.",
            at: NSRect(x: left, y: y, width: width, height: 18)
        ))
        y -= 40

        root.addSubview(heading("History", at: NSRect(x: left, y: y, width: width, height: 20)))
        y -= 26

        let toggle = NSButton(
            checkboxWithTitle: "Keep a local record of every rephrase",
            target: self,
            action: #selector(toggleHistory)
        )
        toggle.frame = NSRect(x: left, y: y, width: width, height: 20)
        root.addSubview(toggle)
        historyToggle = toggle
        y -= 22

        root.addSubview(caption(
            "Stays on this Mac, readable only by you. This file records text you "
                + "typed in other apps.",
            at: NSRect(x: left, y: y, width: width, height: 32)
        ))
        y -= 40

        let clear = NSButton(title: "Clear history", target: self, action: #selector(clearHistory))
        clear.bezelStyle = .rounded
        clear.frame = NSRect(x: left, y: y, width: 120, height: 30)
        root.addSubview(clear)

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: left + width - 100, y: y, width: 100, height: 30)
        root.addSubview(save)
        y -= 30

        let status = caption("", at: NSRect(x: left, y: y, width: width, height: 18))
        root.addSubview(status)
        statusLabel = status

        return root
    }

    private func heading(_ text: String, at frame: NSRect) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.frame = frame
        return field
    }

    private func caption(_ text: String, at frame: NSRect) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.frame = frame
        return field
    }

    // MARK: - Values

    private func loadCurrentValues() {
        // Show that a key exists without displaying it. Reading a stored secret
        // back onto the screen is an unnecessary way to leak it.
        keyField?.placeholderString = Keychain.hasAPIKey ? "•••••••• (saved)" : "sk-…"
        keyField?.stringValue = ""
        modelField?.stringValue = Settings.model
        historyToggle?.state = (history?.isEnabled ?? true) ? .on : .off
        refreshStatus()
    }

    private func refreshStatus() {
        let count = history?.count ?? 0
        let keyState = Keychain.hasAPIKey ? "Key saved" : "No key yet"
        statusLabel?.stringValue = "\(keyState) · \(count) rephrases recorded"
    }

    // MARK: - Actions

    @objc private func save() {
        let typed = keyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !typed.isEmpty {
            do {
                try Keychain.storeAPIKey(typed)
                keyField?.stringValue = ""
            } catch {
                statusLabel?.stringValue = "Could not save key: \(error.localizedDescription)"
                statusLabel?.textColor = .systemRed
                return
            }
        }

        let model = modelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Settings.model = model.isEmpty ? Settings.defaultModel : model
        modelField?.stringValue = Settings.model

        statusLabel?.textColor = .secondaryLabelColor
        loadCurrentValues()
        statusLabel?.stringValue = "Saved. \(history?.count ?? 0) rephrases recorded."
    }

    @objc private func toggleHistory(_ sender: NSButton) {
        history?.isEnabled = (sender.state == .on)
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "This permanently deletes every recorded rephrase. It cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        history?.clear()
        refreshStatus()
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
