import AppKit
import RephrazeKit

// Menu-bar-only app: .accessory means no Dock icon and no menu bar menus,
// which also keeps us from stealing focus from whatever you are typing in.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
