import AppKit
import RephrazeKit

// Menu-bar-only app: .accessory means no Dock icon and no menu bar menus,
// which also keeps us from stealing focus from whatever you are typing in.
// Windows temporarily switch to .regular so they can take focus.
//
// MainActor.assumeIsolated: top-level code in main.swift already runs on the
// main thread, but the compiler cannot infer that on its own.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)

    // Held for the process lifetime; NSApplication only keeps a weak delegate.
    objc_setAssociatedObject(app, "rephraze.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

    app.run()
}
