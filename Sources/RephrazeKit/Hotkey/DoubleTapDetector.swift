import Foundation

/// Turns a stream of solo taps into double-taps.
///
/// A single ⌘ tap happens by accident all the time -- you reach for a shortcut
/// and change your mind. Requiring two taps in quick succession makes
/// accidental firing rare without needing any modifier combination.
///
/// The clock is passed in rather than read internally, so tests are exact
/// instead of sleepy.
public struct DoubleTapDetector {

    /// How long the second tap has to arrive. macOS uses roughly this for
    /// double-clicks, so it matches muscle memory.
    public static let defaultWindow: TimeInterval = 0.4

    private let window: TimeInterval
    private var lastTapAt: TimeInterval?

    public init(window: TimeInterval = DoubleTapDetector.defaultWindow) {
        self.window = window
    }

    /// Register a solo tap. Returns true if it completed a double-tap.
    public mutating func registerTap(at time: TimeInterval) -> Bool {
        defer { }

        if let previous = lastTapAt, time - previous <= window {
            // Consume both taps, so a third tap starts a fresh pair rather than
            // firing again immediately.
            lastTapAt = nil
            return true
        }

        lastTapAt = time
        return false
    }

    public mutating func reset() {
        lastTapAt = nil
    }
}
