import AppKit

/// The menu bar icon and its dropdown.
public final class StatusMenu: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let hotkeyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let tapCountItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lastCaptureItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let previewItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private var lastCaptureSummary = "Nothing captured yet"
    private var lastCapturePreview: String?

    private var tapCount = 0
    private var flashWorkItem: DispatchWorkItem?

    /// Asked at menu-open time so the menu reflects live state.
    public var isHotkeyRunning: () -> Bool = { false }

    /// Shown in the menu, e.g. "⌘".
    public var triggerName: () -> String = { "⌘" }

    /// Called when the user clicks the permission row.
    public var onRequestPermission: () -> Void = {}

    public var onOpenSettings: () -> Void = {}

    private static let idleSymbol = "wand.and.sparkles"
    private static let activeSymbol = "checkmark.circle.fill"
    private static let rejectedSymbol = "slash.circle"

    public override init() {
        super.init()
    }

    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.symbol(Self.idleSymbol)
        item.menu = buildMenu()
        statusItem = item
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: AppInfo.name)
        // Template images adapt to light and dark menu bars automatically.
        image?.isTemplate = true
        return image
    }

    // MARK: - Feedback

    /// Blink the icon so the trigger is visibly acknowledged.
    public func flashTap(success: Bool) {
        tapCount += 1
        refreshTapCount()

        flashWorkItem?.cancel()
        statusItem?.button?.image = Self.symbol(
            success ? Self.activeSymbol : Self.rejectedSymbol
        )

        let restore = DispatchWorkItem { [weak self] in
            self?.statusItem?.button?.image = Self.symbol(Self.idleSymbol)
        }
        flashWorkItem = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: restore)
    }

    /// Record what the last trigger found.
    ///
    /// The captured text is shown here and nowhere else -- deliberately never
    /// written to the system log, which would persist your typing to disk.
    public func setLastCapture(summary: String, preview: String?) {
        lastCaptureSummary = summary
        lastCapturePreview = preview
        refreshCaptureItems()
    }

    private func refreshCaptureItems() {
        lastCaptureItem.title = lastCaptureSummary
        if let preview = lastCapturePreview, !preview.isEmpty {
            previewItem.title = "  “\(preview)”"
            previewItem.isHidden = false
        } else {
            previewItem.isHidden = true
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(
            title: "\(AppInfo.name) \(AppInfo.version)",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        permissionItem.action = #selector(handlePermissionClick)
        permissionItem.target = self
        menu.addItem(permissionItem)

        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)

        tapCountItem.isEnabled = false
        menu.addItem(tapCountItem)

        menu.addItem(.separator())

        lastCaptureItem.isEnabled = false
        menu.addItem(lastCaptureItem)

        previewItem.isEnabled = false
        menu.addItem(previewItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(handleOpenSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit \(AppInfo.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        return menu
    }

    /// Refresh on open, so revoking access in System Settings shows up here
    /// without relaunching.
    public func menuWillOpen(_ menu: NSMenu) {
        refreshPermissionItem()
        refreshHotkeyItem()
        refreshTapCount()
        refreshCaptureItems()
    }

    private func refreshPermissionItem() {
        if Permissions.isTrusted {
            permissionItem.title = "Accessibility access granted"
            permissionItem.isEnabled = false
        } else {
            permissionItem.title = "Grant Accessibility access…"
            permissionItem.isEnabled = true
        }
    }

    private func refreshHotkeyItem() {
        let key = triggerName()
        hotkeyItem.title = isHotkeyRunning()
            ? "Listening — double-tap \(key)"
            : "Not listening — needs Accessibility"
    }

    private func refreshTapCount() {
        tapCountItem.title = tapCount == 1
            ? "1 trigger seen"
            : "\(tapCount) triggers seen"
    }

    @objc private func handleOpenSettings() {
        onOpenSettings()
    }

    @objc private func handlePermissionClick() {
        guard !Permissions.isTrusted else { return }
        onRequestPermission()
    }
}
