import Foundation

/// The four rewrites offered for any piece of text.
///
/// Four is a deliberate number: enough to cover the tones people actually
/// switch between, few enough to scan in a second without deliberating.
public enum RephraseVariant: String, CaseIterable, Codable, Identifiable, Sendable {
    case polished
    case concise
    case professional
    case friendly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .polished:     return "Polished"
        case .concise:      return "Concise"
        case .professional: return "Professional"
        case .friendly:     return "Friendly"
        }
    }

    public var subtitle: String {
        switch self {
        case .polished:     return "Your tone, cleaned up"
        case .concise:      return "Shorter and tighter"
        case .professional: return "Formal, for work"
        case .friendly:     return "Warm and casual"
        }
    }

    public var symbol: String {
        switch self {
        case .polished:     return "sparkles"
        case .concise:      return "scissors"
        case .professional: return "briefcase"
        case .friendly:     return "hand.wave"
        }
    }

    /// Number key that picks this one.
    public var shortcutDigit: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// What the model is told to produce for this variant.
    var instruction: String {
        switch self {
        case .polished:
            return "Same tone and length as the original, just better written. "
                + "Fix grammar and awkward phrasing. Change as little as possible."
        case .concise:
            return "Noticeably shorter. Cut filler and repetition while keeping "
                + "every piece of information."
        case .professional:
            return "Formal and businesslike, suitable for a work email. "
                + "No slang, no contractions."
        case .friendly:
            return "Warm, casual and approachable, as if writing to a colleague "
                + "you like. Contractions are fine."
        }
    }
}

/// A complete set of rewrites for one piece of text.
public struct RephraseSet: Sendable {
    public let original: String
    public let variants: [RephraseVariant: String]

    public init(original: String, variants: [RephraseVariant: String]) {
        self.original = original
        self.variants = variants
    }

    /// Variants that actually came back, in display order.
    public var available: [(variant: RephraseVariant, text: String)] {
        RephraseVariant.allCases.compactMap { variant in
            guard let text = variants[variant]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }
            return (variant, text)
        }
    }

    public var isEmpty: Bool { available.isEmpty }
}
