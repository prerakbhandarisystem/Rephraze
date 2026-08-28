import AppKit
import ServiceManagement

/// Whether macOS starts the app when you log in.
///
/// There is no preference behind this. macOS owns the answer -- the login item
/// is registered with the system, and the system is the only thing that knows
/// whether it stuck, or whether the user later switched it off in System
/// Settings. Keeping a copy in `UserDefaults` would give us a second answer
/// that drifts from the real one, and a switch that lies about itself is worse
/// than no switch.
public enum LoginItem {

    /// True when the app is registered to launch at login.
    public static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// False when there is nothing macOS could register.
    ///
    /// A bare executable from `swift run` has no bundle, and `SMAppService`
    /// raises rather than returning an error when asked about one. The settings
    /// screen reads this so it can say why the switch is off rather than
    /// offering one that cannot work.
    public static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Register or unregister, returning what macOS actually did.
    ///
    /// The return value is the point. Registering can fail -- an unsigned
    /// build, a copy still sitting in the Downloads folder -- and the caller
    /// has to show the real state afterwards rather than the one it asked for.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }
}

/// Whether the app keeps a Dock icon.
///
/// ## Why this is not just the Info.plist
/// `LSUIElement` decides what the app is at launch; the activation policy
/// decides what it is right now, and the two have to agree once the user has an
/// opinion. The plist stays `true` -- a menu bar app is what this is by default
/// -- and this raises the policy at startup for anyone who asked for more.
///
/// Every window that opens has to route its own "put the icon back afterwards"
/// through `apply()` rather than hard-coding `.accessory`, or closing Settings
/// would quietly undo the user's choice.
@MainActor
public enum DockPresence {

    /// Bring the app's Dock presence in line with the preference.
    public static func apply() {
        NSApp.setActivationPolicy(Settings.showsInDock ? .regular : .accessory)
    }

    /// Show the icon for as long as a window is open, whatever the preference.
    ///
    /// A window belonging to an app with no Dock icon cannot be reached with
    /// ⌘-Tab, so it is lost the moment anything covers it. The icon comes back
    /// out for the window's lifetime and `apply()` puts it away afterwards.
    public static func raiseForWindow() {
        NSApp.setActivationPolicy(.regular)
    }
}
