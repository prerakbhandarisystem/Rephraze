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

    /// Where the panel's bottom edge and horizontal centre should stay.
    ///
    /// The panel sits just above the text being edited, so the bottom edge is
    /// the one that matters: pin that, and streaming content grows the panel
    /// upward into empty screen instead of downward over the text field it
    /// belongs to. AppKit already positions windows by their bottom-left
    /// corner, so this is also the cheap direction to hold.
    private var anchorBottomCentre: NSPoint?
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
        endEditing(restoringFocusTo: nil)
        panel?.orderOut(nil)
        anchorBottomCentre = nil
    }

    /// Take keyboard focus so the user can type a follow-up instruction.
    ///
    /// This is the one moment the panel is allowed to steal focus. The caret
    /// leaves their text field, so the app must be re-activated and the write
    /// aimed at the stored element afterwards -- see `endEditing`.
    public func beginEditing() {
        guard let panel, !model.isEditing else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.isEditing = true
    }

    /// Give focus back to the app the text came from.
    ///
    /// Without this the paste fallback would fire while Rephraze itself is
    /// frontmost, and the rewrite would go nowhere.
    public func endEditing(restoringFocusTo pid: pid_t?) {
        guard model.isEditing else { return }
        model.isEditing = false
        panel?.resignKey()

        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        } else {
            NSApp.hide(nil)
        }
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
                self.keepAnchored(panel)
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
        keepAnchored(panel)
    }

    deinit {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        sizeSync?.cancel()
    }

    /// Centre the panel horizontally and sit it just above the text field.
    ///
    /// Centred because that is where the eye already is, and directly above the
    /// field so the connection between the two is obvious without the panel
    /// ever covering what is being rewritten. If there is not enough room above
    /// -- a field near the top of the screen -- `clamp` slides it down, and it
    /// overlaps rather than falling off the edge.
    private func position(_ panel: NSPanel, near field: FocusedField?) {
        panel.layoutIfNeeded()
        let size = panel.frame.size

        // Use the screen the text is on, so this behaves on a second display.
        let screen = fieldScreen(field) ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        let gap: CGFloat = 14
        let bottom: CGFloat
        if let field, let frame = fieldFrame(field) {
            // Accessibility reports top-left origin; AppKit is bottom-left.
            let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let fieldTop = screenHeight - frame.minY
            bottom = fieldTop + gap
        } else {
            // No field to sit above: centre it and be done.
            bottom = visible.midY - size.height / 2
        }

        let origin = NSPoint(x: visible.midX - size.width / 2, y: bottom)
        let clamped = clamp(origin, size: size)
        anchorBottomCentre = NSPoint(x: clamped.x + size.width / 2, y: clamped.y)
        panel.setFrameOrigin(clamped)

        // Positioning depends on what the other app is willing to tell us, and
        // silently falls back when it says nothing. Log which happened.
        let located = field.flatMap { fieldFrame($0) } != nil
        Log.app.notice("""
            Panel placed: field=\(located ? "located" : "UNKNOWN, centred instead", privacy: .public) \
            size=\(Int(size.width))x\(Int(size.height)) \
            wanted_y=\(Int(origin.y)) got_y=\(Int(clamped.y)) \
            clamped=\(abs(origin.y - clamped.y) > 1 ? "YES" : "no", privacy: .public)
            """)
    }

    /// Re-apply the stored anchor after the content changes size.
    ///
    /// Holds the bottom edge and the centre line, so the panel grows upward and
    /// outward symmetrically rather than drifting.
    private func keepAnchored(_ panel: NSPanel) {
        guard let anchorBottomCentre else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: anchorBottomCentre.x - size.width / 2,
            y: anchorBottomCentre.y
        )
        let clamped = clamp(origin, size: size)
        if panel.frame.origin != clamped {
            panel.setFrameOrigin(clamped)
        }

        // If the panel grew tall enough to hit the top of the screen, clamp
        // drags it back down -- over the field it is supposed to sit above.
        if abs(origin.y - clamped.y) > 1 {
            Log.app.notice("""
                Panel outgrew the space above the field: \
                height=\(Int(size.height)) wanted_y=\(Int(origin.y)) got_y=\(Int(clamped.y))
                """)
        }
    }

    /// Which screen the text being rewritten is on.
    private func fieldScreen(_ field: FocusedField?) -> NSScreen? {
        guard let field, let frame = fieldFrame(field) else { return nil }
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let point = NSPoint(x: frame.midX, y: screenHeight - frame.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
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
