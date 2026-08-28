import AppKit
import SwiftUI

/// Hosts the SwiftUI settings + history interface in a real window.
public final class SettingsWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var model: SettingsModel?

    public var history: HistoryStore?
    /// The app's one reporter. Sharing the instance matters: two of them would
    /// keep two queues over the same file and lose each other's events.
    public var telemetry: Telemetry?

    /// Called when the trigger key or its timing changes, so the running event
    /// tap can be rebuilt. Owned by whoever owns the tap.
    public var onHotkeyChanged: () -> Void = {}

    public override init() {
        super.init()
    }

    /// Open the window.
    ///
    /// - Parameter tab: which tab to land on. Chosen by what is missing: no key
    ///   means nothing works yet, no voice means the most valuable thing is
    ///   still unset, and otherwise the interesting content is what the app has
    ///   been doing.
    @MainActor
    public func show(section: SettingsSection? = nil) {
        let landing = section ?? {
            // Account, not General: the key is what is missing, and the key
            // lives there now.
            if !Keychain.hasAPIKey { return SettingsSection.account }
            if Settings.style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .style
            }
            return .history
        }()

        if let existing = window, let model {
            model.refresh()
            model.selectedSection = landing
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let history, let telemetry else { return }

        // Up for as long as this window is open, whatever the preference: a
        // window belonging to an app with no Dock icon cannot be reached with
        // ⌘-Tab, so it would be lost the moment anything covered it.
        DockPresence.raiseForWindow()

        let model = SettingsModel(history: history, telemetry: telemetry)
        model.selectedSection = landing
        model.onHotkeyChanged = { [weak self] in self?.onHotkeyChanged() }
        self.model = model

        let root = SettingsView(model: model) { [weak self] in
            self?.close()
        }

        let controller = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: controller)
        win.title = "Rephraze"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]

        // No strip of its own above the window: the content runs the full
        // height and the title bar is drawn over it, so the close and minimise
        // buttons sit on the sidebar's cream rather than on a grey band that
        // stops where the sidebar starts. That band was the one seam left in
        // the window.
        win.titlebarAppearsTransparent = true
        // The sidebar already says "Rephraze" in type twice the size, and a
        // centred title over a transparent bar reads as floating text.
        win.titleVisibility = .hidden
        // One row rather than a title above a toolbar, now that there is no
        // title to sit above it.
        win.toolbarStyle = .unified

        // Open large: the History tab is a reading view, and a cramped window
        // makes long rewrites unreadable. Roughly three quarters of the screen,
        // capped so it stays sane on a very large display.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let width = min(max(visible.width * 0.72, 900), 1400)
            let height = min(max(visible.height * 0.78, 620), 1000)
            win.setContentSize(NSSize(width: width, height: height))
        } else {
            win.setContentSize(NSSize(width: 980, height: 700))
        }
        win.minSize = NSSize(width: 720, height: 520)
        win.center()
        win.delegate = self
        win.isReleasedWhenClosed = false

        window = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    public func close() {
        window?.close()
    }

    /// Refresh the history list if the window happens to be open when a new
    /// rephrase lands.
    @MainActor
    public func refreshIfVisible() {
        guard window?.isVisible == true else { return }
        model?.refresh()
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
        model = nil
        // Back to whatever the user asked for in System, rather than always to
        // accessory -- that would quietly undo a Dock icon they turned on.
        DockPresence.apply()
    }
}
