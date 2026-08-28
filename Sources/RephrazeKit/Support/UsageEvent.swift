import Foundation

/// Everything the app is willing to report about itself.
///
/// ## Why this is an enum and not a dictionary
/// A `[String: Any]` event API would work, and the first time someone wanted to
/// debug a bad rewrite they would put the text in it. The promise this app
/// makes is that what you type never leaves the Mac, and a promise that depends
/// on everyone remembering it is not a promise. So the payload is a closed set
/// of cases carrying enums, counts and flags — there is no case that takes
/// arbitrary text, which makes leaking a sentence a compile error rather than a
/// code review.
public enum UsageEvent: Equatable {

    /// The app started. One per launch — this is what a daily-active count is
    /// built from.
    case launched

    /// A rephrase ran to a conclusion, however it ended.
    case rephrased(outcome: Outcome, personalised: Bool, milliseconds: Int)

    /// A rewrite was translated into another language.
    case translated(language: TargetLanguage)

    /// Something went wrong, described by kind and nothing else — never the
    /// message, which can quote the text that caused it.
    case failed(reason: FailureReason)

    public enum Outcome: String, Equatable {
        /// The user took the rewrite.
        case accepted
        /// The user pressed esc, or triggered again over the top.
        case dismissed
    }

    /// Where it went wrong, at the coarsest grain that is actually populated.
    ///
    /// Network-versus-service would be more useful and is deliberately absent:
    /// telling them apart needs the `Error` from the request, which is not in
    /// hand at the point these are recorded. A reason that is never set is
    /// worse on a dashboard than one that is missing.
    public enum FailureReason: String, Equatable {
        /// The rewrite itself did not arrive.
        case rephrase
        /// A rewrite arrived, and putting it back into the other app failed.
        /// The one that matters most here — it means Accessibility or the
        /// paste path broke in some app, and the user got nothing.
        case write
    }

    var name: String {
        switch self {
        case .launched:   return "launched"
        case .rephrased:  return "rephrased"
        case .translated: return "translated"
        case .failed:     return "failed"
        }
    }

    var properties: [String: UsageValue] {
        switch self {
        case .launched:
            return [:]

        case let .rephrased(outcome, personalised, milliseconds):
            return [
                "outcome": .text(outcome.rawValue),
                "personalised": .flag(personalised),
                // Clamped rather than trusted: a machine asleep mid-request
                // should not report a rephrase that took four hours.
                "milliseconds": .number(min(max(milliseconds, 0), 120_000)),
            ]

        case let .translated(language):
            return ["language": .text(language.rawValue)]

        case let .failed(reason):
            return ["reason": .text(reason.rawValue)]
        }
    }
}

/// The only shapes a property can take. Deliberately not `String` for
/// everything: the dashboard has to average durations, and parsing numbers back
/// out of strings on the server is how the wrong thing gets averaged.
public enum UsageValue: Codable, Equatable {
    case text(String)
    case number(Int)
    case flag(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool before Int: JSONDecoder will happily read `true` as 1.
        if let flag = try? container.decode(Bool.self) {
            self = .flag(flag)
        } else if let number = try? container.decode(Int.self) {
            self = .number(number)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value):   try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .flag(value):   try container.encode(value)
        }
    }
}

/// One event, stamped and queued.
public struct RecordedEvent: Codable, Equatable {
    public let name: String
    public let at: Date
    public let properties: [String: UsageValue]

    public init(_ event: UsageEvent, at: Date = Date()) {
        self.name = event.name
        self.at = at
        self.properties = event.properties
    }
}

/// What actually goes over the wire.
///
/// The install id is a random UUID made on this Mac and stored in preferences.
/// It is not derived from the hardware, the login, the email address or the
/// serial number — nothing about it can be turned back into a person, and
/// resetting it in Settings makes this install a new one as far as any
/// dashboard is concerned.
public struct UsageBatch: Codable, Equatable {
    public let installID: String
    public let appVersion: String
    public let system: String
    public let events: [RecordedEvent]
}
