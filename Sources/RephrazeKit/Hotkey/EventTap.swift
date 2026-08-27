import AppKit
import CoreGraphics

/// Which modifier key triggers Rephraze.
public enum TriggerKey: String, CaseIterable {
    case command
    case option
    case control
    case function

    var flag: CGEventFlags {
        switch self {
        case .command:  return .maskCommand
        case .option:   return .maskAlternate
        case .control:  return .maskControl
        case .function: return .maskSecondaryFn
        }
    }

    /// Every modifier that is *not* this one. Holding any of them means the user
    /// is doing a shortcut, not tapping.
    var disqualifyingFlags: [CGEventFlags] {
        let all: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskControl,
                                   .maskShift, .maskSecondaryFn]
        return all.filter { $0 != flag }
    }

    public var displayName: String {
        switch self {
        case .command:  return "⌘"
        case .option:   return "⌥"
        case .control:  return "⌃"
        case .function: return "fn"
        }
    }
}

/// The single keyboard listener the whole app runs on.
///
/// It does two jobs, because our floating panel deliberately never takes focus
/// and therefore cannot receive keys the normal way:
///   1. spot taps of the trigger key -- single and double
///   2. catch `esc` while the panel is open, and swallow it
///
/// ## This callback must stay fast
/// macOS switches off an event tap whose callback is slow
/// (`tapDisabledByTimeout`), and a dead tap is a dead app. So the callback only
/// decides *whether* something happened and hands the real work to the main
/// queue. It also listens for being switched off and turns itself back on.
public final class EventTap {

    public enum Signal {
        /// Trigger key tapped once on its own.
        case soloTap
        /// Two solo taps inside the double-tap window.
        case doubleTap
        case escape
    }

    /// Set to true while the panel is open, so `esc` gets swallowed instead of
    /// reaching the app underneath. Read synchronously inside the callback.
    public var wantsEscape = false

    public let trigger: TriggerKey

    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var monitor = SoloTapMonitor()
    private var doubleTap = DoubleTapDetector()
    private let onSignal: (Signal) -> Void

    private static let escapeKeyCode: Int64 = 53

    public init(trigger: TriggerKey = .command, onSignal: @escaping (Signal) -> Void) {
        self.trigger = trigger
        self.onSignal = onSignal
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Start listening. Returns false if macOS refused, which in practice always
    /// means Accessibility permission is missing.
    @discardableResult
    public func start() -> Bool {
        guard tapPort == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        // .defaultTap (not .listenOnly) because we need the ability to swallow
        // esc. Everything else passes straight through untouched.
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("Could not create event tap -- Accessibility permission missing?")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tapPort = port
        runLoopSource = source
        Log.hotkey.notice("Event tap started, trigger = \(self.trigger.rawValue, privacy: .public)")
        return true
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port = tapPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        runLoopSource = nil
        tapPort = nil
    }

    public var isRunning: Bool {
        guard let port = tapPort else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    // MARK: - Callback

    fileprivate func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        // macOS switched us off. Turn back on, and forget any half-seen press
        // since we may have missed its release.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.hotkey.warning("Event tap disabled (\(type.rawValue)) -- re-arming")
            monitor.reset()
            doubleTap.reset()
            if let port = tapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            let flags = event.flags
            let others = trigger.disqualifyingFlags.contains { flags.contains($0) }
            let input = SoloTapMonitor.Input.flags(
                target: flags.contains(trigger.flag),
                others: others
            )

            if monitor.handle(input) == .soloTap {
                // Monotonic clock -- unaffected by the wall clock changing.
                let now = ProcessInfo.processInfo.systemUptime
                if doubleTap.registerTap(at: now) {
                    Log.hotkey.notice("DOUBLE tap")
                    emit(.doubleTap)
                } else {
                    Log.hotkey.notice("solo tap")
                    emit(.soloTap)
                }
            }
            // Never swallow: doing so would break every ⌘ shortcut on the Mac.
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            if wantsEscape && keyCode == Self.escapeKeyCode {
                emit(.escape)
                return nil  // swallow, so esc does not also reach the app below
            }

            _ = monitor.handle(.keyDown)
            return Unmanaged.passUnretained(event)

        case .leftMouseDown, .rightMouseDown:
            _ = monitor.handle(.otherInput)
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Hand off to the main queue so the tap callback returns immediately.
    private func emit(_ signal: Signal) {
        let handler = onSignal
        DispatchQueue.main.async { handler(signal) }
    }
}

/// C function pointer -- cannot capture context, so `self` arrives via refcon.
private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
