import Foundation

/// How many rewrites someone has taken, against how many they were given.
///
/// ## What counts as one
/// A rewrite that actually landed in their text field. A capture they dismissed,
/// or one that failed on the way back, costs nothing -- they got nothing, so
/// they are charged nothing. That also makes the four-tone path one rewrite
/// rather than four: reading the options is free, and only the one they take is
/// counted. A follow-up in the conversation is likewise free until they apply
/// something out of it.
///
/// ## What this is not
/// It is not enforcement, and it is deliberately not written as though it were.
/// The count lives in this Mac's preferences, which the person it counts can
/// clear; the app already hands out `resetInstallID` on the principle that
/// identity here is disposable. Treated as a lock this would be a lock with the
/// key taped beside it. Treated as what it is -- a visible allowance, shown
/// where someone will see it -- it is honest, and it is the number worth
/// watching before deciding whether fifty is the right number.
public struct UsageQuota {

    /// Rewrites included. One number in one place: changing the allowance is
    /// changing this line.
    public static let allowance = 50

    /// How few may be left before it is worth saying so unprompted.
    ///
    /// Silence until then is the point. A counter on screen from the first
    /// rewrite would make every rewrite feel metered, which is a worse
    /// experience than the limit itself.
    public static let lowWaterMark = 10

    private static let usedKey = "rewritesApplied"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// How many have been taken.
    ///
    /// Not capped at the allowance. Nothing here blocks, so someone can pass
    /// fifty -- and by how far is exactly the interesting number.
    public var used: Int {
        max(0, defaults.integer(forKey: Self.usedKey))
    }

    /// How many are left, floored at zero.
    public var remaining: Int {
        max(0, Self.allowance - used)
    }

    public var isExhausted: Bool { remaining == 0 }

    /// Worth mentioning without being asked.
    public var isRunningLow: Bool { remaining <= Self.lowWaterMark }

    /// Count one rewrite that reached the user's text field.
    public func recordApplied() {
        defaults.set(used + 1, forKey: Self.usedKey)
    }

    /// Put the allowance back. Not wired to anything the user can press -- it
    /// exists so tests can start from a known count.
    public func reset() {
        defaults.removeObject(forKey: Self.usedKey)
    }
}
