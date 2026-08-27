import AppKit
import SwiftUI
import ApplicationServices

/// The floating picker window.
///
/// ## It must never take focus
/// The whole trick is that your text box stays focused underneath. The moment
/// this panel becomes key, the field below loses its selection and often its
/// caret, and putting text back becomes unreliable.
///
/// So: `.nonactivatingPanel`, and the app stays `.accessory` throughout. Mouse
/// clicks still work in a non-activating panel. Keyboard does not — the number
/// keys and `esc` are delivered by the event tap instead.
@MainActor
public final class ResultPanel {

    private var panel: NSPanel?
    public let model = ResultPanelModel()

    public var isVisible: Bool { panel?.isVisible ?? false }

    public init() {}

    public func show(near field: FocusedField?) {
        let panel = existingOrNew()

        position(panel, near: field)
        // orderFrontRegardless, not makeKeyAndOrderFront: we want it visible
        // without becoming key.
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    private func existingOrNew() -> NSPanel {
        if let panel { return panel }

        let hosting = NSHostingController(rootView: ResultPanelView(model: model))
        hosting.view.setFrameSize(hosting.view.fittingSize)

        let created = NSPanel(contentViewController: hosting)
        created.styleMask = [.nonactivatingPanel, .fullSizeContentView, .borderless]
        created.isFloatingPanel = true
        created.level = .floating
        created.hidesOnDeactivate = false
        created.becomesKeyOnlyIfNeeded = true
        created.isMovableByWindowBackground = true
        created.backgroundColor = .clear
        created.isOpaque = false
        created.hasShadow = false          // SwiftUI draws its own
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        // Follow the user across Spaces rather than pinning to one.
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        panel = created
        return created
    }

    /// Put the panel just under the text box it belongs to, so the connection
    /// is obvious. Falls back to the pointer when the field will not say where
    /// it is.
    private func position(_ panel: NSPanel, near field: FocusedField?) {
        panel.layoutIfNeeded()
        let panelSize = panel.frame.size

        let anchor: NSPoint
        if let field, let frame = fieldFrame(field) {
            // Screen coordinates from Accessibility are top-left origin; AppKit
            // is bottom-left. Convert using the primary screen's height.
            let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
            anchor = NSPoint(
                x: frame.minX,
                y: screenHeight - frame.maxY - panelSize.height - 8
            )
        } else {
            let mouse = NSEvent.mouseLocation
            anchor = NSPoint(x: mouse.x, y: mouse.y - panelSize.height - 12)
        }

        panel.setFrameOrigin(clamp(anchor, size: panelSize))
    }

    /// Where the focused field is on screen, if it will tell us.
    private func fieldFrame(_ field: FocusedField) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
                field.element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(
                field.element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue, let sizeValue,
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: origin, size: size)
    }

    /// Keep the whole panel on screen.
    private func clamp(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: origin.x, y: origin.y + size.height))
        }) ?? NSScreen.main else {
            return origin
        }

        let visible = screen.visibleFrame
        var point = origin
        point.x = min(max(point.x, visible.minX + 8), visible.maxX - size.width - 8)
        point.y = min(max(point.y, visible.minY + 8), visible.maxY - size.height - 8)
        return point
    }
}
