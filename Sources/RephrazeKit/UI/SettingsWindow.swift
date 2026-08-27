import AppKit
import SwiftUI

/// Hosts the SwiftUI settings + history interface in a real window.
public final class SettingsWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var model: SettingsModel?

    public var history: HistoryStore?

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
    public func show(tab: SettingsTab? = nil) {
        let landing = tab ?? {
            if !Keychain.hasAPIKey { return SettingsTab.general }
            if Settings.style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .style
            }
            return .history
        }()

        if let existing = window, let model {
            model.refresh()
            model.selectedTab = landing
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let history else { return }

        NSApp.setActivationPolicy(.regular)

        let model = SettingsModel(history: history)
        model.selectedTab = landing
        self.model = model

        let root = SettingsView(model: model) { [weak self] in
            self?.close()
        }

        let controller = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: controller)
        win.title = "Rephraze"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]

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
        NSApp.setActivationPolicy(.accessory)
    }
}
