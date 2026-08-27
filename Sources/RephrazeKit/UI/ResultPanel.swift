import AppKit
import SwiftUI
import Combine
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
    private var hosting: NSHostingController<ResultPanelView>?
    private var sizeSync: AnyCancellable?
    public let model = ResultPanelModel()

    /// Where the panel's top-left corner should stay.
    ///
    /// AppKit positions windows by their bottom-left corner, so a panel that
    /// grows -- which this one does constantly, as four variants stream in --
    /// creeps upward over the very text it belongs to. Keeping the top edge
    /// pinned instead means it grows downward, away from your writing.
    private var anchorTopLeft: NSPoint?
    private var resizeObserver: NSObjectProtocol?

    public var isVisible: Bool { panel?.isVisible ?? false }

    public init() {}

    public func show(near field: FocusedField?) {
        let panel = existingOrNew()

        // Lay out at the current content size before measuring.
        panel.layoutIfNeeded()
        position(panel, near: field)
        // orderFrontRegardless, not makeKeyAndOrderFront: we want it visible
        // without becoming key.
        panel.orderFrontRegardless()
        resizeToFitContent()
        Log.app.notice("Panel shown at \(Int(panel.frame.width))x\(Int(panel.frame.height))")
    }

    public func hide() {
        panel?.orderOut(nil)
        anchorTopLeft = nil
    }

    private func existingOrNew() -> NSPanel {
        if let panel { return panel }

        let hosting = NSHostingController(rootView: ResultPanelView(model: model))
        hosting.view.setFrameSize(hosting.view.fittingSize)
        self.hosting = hosting

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

        // The panel resizes on every streamed chunk. Re-pin the top each time.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: created,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.keepTopEdgeFixed(panel)
            }
        }

        // A borderless panel does not reliably follow its SwiftUI content as
        // that content grows. Drive the size explicitly instead: every model
        // change re-measures the view and resizes the window to match.
        sizeSync = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizeToFitContent()
            }

        panel = created
        return created
    }

    /// Match the window to whatever the SwiftUI content now wants to be.
    public func resizeToFitContent() {
        guard let panel, let hosting, panel.isVisible else { return }

        let fitting = hosting.view.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }
        guard abs(panel.frame.size.height - fitting.height) > 0.5
                || abs(panel.frame.size.width - fitting.width) > 0.5
        else { return }

        panel.setContentSize(fitting)
        keepTopEdgeFixed(panel)
    }

    deinit {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        sizeSync?.cancel()
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

            // The field, in AppKit coordinates.
            let fieldBottom = screenHeight - frame.maxY
            let fieldTop = screenHeight - frame.minY

            let visible = (NSScreen.screens.first {
                $0.frame.contains(NSPoint(x: frame.minX, y: fieldBottom))
            } ?? NSScreen.main)?.visibleFrame ?? .zero

            let roomBelow = fieldBottom - visible.minY - 8
            let roomAbove = visible.maxY - fieldTop - 8

            // Below the field by default -- it reads as belonging to it. But
            // the panel is tall now, and a field near the bottom of the screen
            // leaves nowhere to put it; flip above rather than cover the text
            // the user is looking at.
            if panelSize.height <= roomBelow || roomBelow >= roomAbove {
                anchor = NSPoint(x: frame.minX, y: fieldBottom - panelSize.height - 8)
            } else {
                anchor = NSPoint(x: frame.minX, y: fieldTop + 8)
            }
        } else {
            let mouse = NSEvent.mouseLocation
            anchor = NSPoint(x: mouse.x, y: mouse.y - panelSize.height - 12)
        }

        // Remember the top edge, not the bottom.
        let clamped = clamp(anchor, size: panelSize)
        anchorTopLeft = NSPoint(x: clamped.x, y: clamped.y + panelSize.height)
        panel.setFrameOrigin(clamped)
    }

    /// Re-apply the stored top-left after the content changes size.
    private func keepTopEdgeFixed(_ panel: NSPanel) {
        guard let anchorTopLeft else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: anchorTopLeft.x, y: anchorTopLeft.y - size.height)
        let clamped = clamp(origin, size: size)
        if panel.frame.origin != clamped {
            panel.setFrameOrigin(clamped)
        }
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
