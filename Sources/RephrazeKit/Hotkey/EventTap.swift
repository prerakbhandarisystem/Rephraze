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
        /// A number key the picker is currently using.
        case digit(Int)
        /// Tab: the user wants to type a follow-up instruction.
        case refine
        /// ⌥T: show the languages this can be written in.
        case translate
        /// Any other typing while the picker is open -- get out of the way.
        case dismiss
    }

    /// True while the picker is open. Number keys and `esc` are then swallowed
    /// and delivered to the panel, which cannot receive them itself because it
    /// never takes focus. Read synchronously inside the callback.
    public var wantsPanelKeys = false

    /// True while the panel holds the keyboard for its own input box.
    ///
    /// The panel is key then, so it receives everything itself and the tap must
    /// keep out of the way -- with one exception. `esc` never reaches our code:
    /// the field editor takes it first, to abandon whatever is half-typed. So
    /// the tap keeps exactly that one key while editing and passes the rest
    /// through untouched, which is what makes "esc to stop typing" work at all.
    public var panelIsEditing = false

    /// How many number keys the picker is using right now.
    ///
    /// Four for the rewrites, ten for the language list, one for a single
    /// result. Only that many are swallowed: pressing "7" over a four-option
    /// picker has to type a 7 into the user's sentence, not vanish into a key
    /// that does nothing. Read synchronously inside the callback, so it is a
    /// plain Int rather than anything that needs the main actor.
    public var panelDigitCount = 0

    public let trigger: TriggerKey

    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var monitor = SoloTapMonitor()
    private var doubleTap = DoubleTapDetector()
    private let onSignal: (Signal) -> Void

    private static let escapeKeyCode: Int64 = 53
    private static let tabKeyCode: Int64 = 48
    private static let tKeyCode: Int64 = 17

    /// Virtual key codes for the number row, 1 through 9 and then 0.
    private static let digitKeyCodes: [Int64: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0,
    ]

    /// Whether a digit means anything to the picker as it currently stands.
    ///
    /// 0 is the tenth key on the row, not the zeroth, which is why this cannot
    /// just compare the digit against the count.
    private func isLivePanelDigit(_ digit: Int) -> Bool {
        (digit == 0 ? 10 : digit) <= panelDigitCount
    }

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

            if panelIsEditing {
                // Tell the monitor a key was pressed, or releasing a modifier
                // after typing would read as a solo tap.
                _ = monitor.handle(.keyDown)
                if keyCode == Self.escapeKeyCode {
                    emit(.escape)
                    return nil
                }
                // Swallowed and ignored. The box is the only thing worth having
                // focus while it is open, and Tab would walk off it to whatever
                // SwiftUI decides is next -- leaving the user typing into
                // nothing, with no sign of where their words went.
                if keyCode == Self.tabKeyCode {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            if wantsPanelKeys {
                let hasModifier = event.flags.contains(.maskCommand)
                    || event.flags.contains(.maskControl)
                    || event.flags.contains(.maskAlternate)

                if keyCode == Self.escapeKeyCode {
                    emit(.escape)
                    return nil  // swallow, so esc does not also reach the app below
                }

                // Tab hands focus to the panel's own input box. Swallowed, or
                // the app underneath would also move its focus ring.
                if !hasModifier, keyCode == Self.tabKeyCode {
                    emit(.refine)
                    return nil
                }

                // ⌥T opens the language list.
                //
                // Not a bare "t". While the picker is up, an unmodified letter
                // means the user carried on typing, and swallowing one would
                // silently drop a character out of the sentence they are
                // writing -- too high a price for one letter's convenience.
                // ⌥ is already this app's key, so ⌥T reads as ours.
                if keyCode == Self.tKeyCode,
                   event.flags.contains(.maskAlternate),
                   !event.flags.contains(.maskCommand),
                   !event.flags.contains(.maskControl) {
                    // The trigger key is down. Tell the monitor a key was
                    // pressed, or releasing ⌥ afterwards would read as a solo
                    // tap and could complete a phantom double-tap.
                    _ = monitor.handle(.keyDown)
                    emit(.translate)
                    return nil
                }

                // A bare number picks an option, but only one the picker is
                // actually offering. With a modifier held it is a real shortcut
                // (⌘1 switches tabs) and must pass through untouched.
                if !hasModifier,
                   let digit = Self.digitKeyCodes[keyCode],
                   isLivePanelDigit(digit) {
                    emit(.digit(digit))
                    return nil
                }

                // Anything else means the user moved on. Close the picker, but
                // let the keystroke through -- swallowing it would eat a
                // character out of what they are typing.
                emit(.dismiss)
                _ = monitor.handle(.keyDown)
                return Unmanaged.passUnretained(event)
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
