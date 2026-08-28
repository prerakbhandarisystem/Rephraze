import AppKit

/// Shown at launch while Accessibility access is missing.
///
/// Rephraze normally has no window and no Dock icon, which makes a first launch
/// feel like nothing happened -- the only sign of life is a small menu bar icon
/// that is easy to miss behind a notch or a crowded menu bar. So when the app
/// cannot actually work yet, it says so in a window you cannot miss.
/// Every member touches AppKit, so the whole class is pinned to the main actor
/// rather than each method being annotated one at a time.
@MainActor
public final class OnboardingWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var poll: Timer?

    public var onGranted: () -> Void = {}

    public override init() {
        super.init()
    }

    public func show() {
        Log.app.notice("OnboardingWindow.show() called")
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Temporarily become a normal app so the window can take focus and show
        // up in the Dock. We drop back to .accessory once access is granted.
        DockPresence.raiseForWindow()

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Rephraze Setup"
        win.center()
        win.delegate = self
        win.contentView = buildContent()
        win.isReleasedWhenClosed = false

        window = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        Log.app.notice("Onboarding window ordered front, visible = \(win.isVisible)")

        startPolling()
    }

    public func close() {
        poll?.invalidate()
        poll = nil
        window?.close()
        window = nil
        DockPresence.apply()
    }

    // MARK: - Content

    private func buildContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 340))

        let title = label(
            "Rephraze needs permission",
            font: .systemFont(ofSize: 22, weight: .semibold)
        )
        title.frame = NSRect(x: 32, y: 268, width: 456, height: 30)
        root.addSubview(title)

        let body = label(
            """
            To read the text you are typing, macOS requires Accessibility \
            access. Rephraze cannot see a single keystroke until you turn \
            it on.
            """,
            font: .systemFont(ofSize: 13)
        )
        body.frame = NSRect(x: 32, y: 214, width: 456, height: 48)
        root.addSubview(body)

        let steps = label(
            """
            1.  Click the button below — System Settings opens.
            2.  Find Rephraze in the list. If it is already there, select it
                 and click  −  to remove the stale entry first.
            3.  Click  +  , choose Applications → Rephraze, and switch it on.
            """,
            font: .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        )
        steps.frame = NSRect(x: 32, y: 128, width: 456, height: 76)
        root.addSubview(steps)

        let button = NSButton(
            title: "Open Accessibility Settings",
            target: self,
            action: #selector(openSettings)
        )
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.frame = NSRect(x: 32, y: 84, width: 240, height: 32)
        root.addSubview(button)

        let status = label("Waiting for access…", font: .systemFont(ofSize: 12))
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 32, y: 46, width: 456, height: 20)
        root.addSubview(status)
        statusLabel = status

        let hint = label(
            "This window closes by itself the moment access is granted.",
            font: .systemFont(ofSize: 11)
        )
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 32, y: 20, width: 456, height: 18)
        root.addSubview(hint)

        return root
    }

    private func label(_ text: String, font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        return field
    }

    // MARK: - Actions

    @objc private func openSettings() {
        Permissions.requestAccess()
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Watch for the grant so the window can dismiss itself, rather than making
    /// the user work out that they are done.
    private func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard Permissions.isTrusted else { return }
            timer.invalidate()

            // The timer was scheduled on the main run loop, so this fires on
            // the main thread -- but the closure itself is nonisolated, and the
            // compiler cannot see the connection. Stated rather than left to
            // warn, since everything below touches AppKit.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.poll = nil
                self.statusLabel?.stringValue = "Access granted."
                self.statusLabel?.textColor = .systemGreen

                // Let the user see the confirmation before it disappears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    MainActor.assumeIsolated {
                        self.onGranted()
                        self.close()
                    }
                }
            }
        }
    }

    public func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
        poll = nil
        window = nil
        DockPresence.apply()
    }
}
