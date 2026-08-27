import Foundation

/// Decides whether a modifier key was tapped *on its own*.
///
/// Modifiers normally come with company: ⌘C, ⌘Tab, fn+arrow. A solo tap means
/// pressed and released with nothing else happening in between.
///
/// ```
/// ⌘ ▼ ................. ⌘ ▲     nothing else pressed  →  solo tap
/// ⌘ ▼ ....... C ....... ⌘ ▲     a key snuck in        →  ignore
/// ```
///
/// The decision happens on release, so there is no artificial latency.
/// Deliberately pure -- no CoreGraphics, no clock, no global state -- so the
/// whole thing is unit testable.
public struct SoloTapMonitor {

    public enum Input: Equatable {
        /// A flagsChanged event. `target` is the modifier we care about;
        /// `others` is any *different* modifier being held.
        case flags(target: Bool, others: Bool)
        /// Any non-modifier key went down.
        case keyDown
        /// Anything else disqualifying, e.g. a mouse click.
        case otherInput
    }

    public enum Output: Equatable {
        case none
        case soloTap
    }

    private var isDown = false
    private var contaminated = false

    public init() {}

    public mutating func handle(_ input: Input) -> Output {
        switch input {
        case let .flags(target, others):
            if target {
                if isDown {
                    // Still held; another modifier joined partway through.
                    if others { contaminated = true }
                } else {
                    // Fresh press. If another modifier was already held, combo.
                    isDown = true
                    contaminated = others
                }
                return .none
            } else {
                // Released. isDown may be false if the key was already held when
                // the app launched -- that correctly yields .none.
                let wasCleanTap = isDown && !contaminated
                isDown = false
                contaminated = false
                return wasCleanTap ? .soloTap : .none
            }

        case .keyDown, .otherInput:
            if isDown { contaminated = true }
            return .none
        }
    }

    /// Forget any in-progress press. Used when the event tap is re-armed after
    /// macOS disables it, since we may have missed the matching release.
    public mutating func reset() {
        isDown = false
        contaminated = false
    }
}
