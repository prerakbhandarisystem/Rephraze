import Foundation

/// Last line of defence between the model and the user's text field.
///
/// The prompt already forbids preambles, code fences and quotation marks, but
/// prompts are guidance rather than a guarantee -- and the text goes straight
/// into whatever the user was typing in, where a stray ``` is not a cosmetic
/// problem but corrupted data. This strips the handful of wrappers a model
/// actually produces when it slips, and does nothing else: it deliberately does
/// not try to detect or repair bad rewrites, only bad packaging.
public enum RewriteSanitizer {

    public static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = strippingCodeFence(text)
        text = strippingWrappingQuotes(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove a ``` fence wrapped around the whole reply.
    ///
    /// Only when it encloses everything. A fence in the middle was probably in
    /// the user's original text, and removing it would change what they wrote.
    private static func strippingCodeFence(_ text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 else {
            return text
        }

        var lines = text.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return text }

        // Opening fence may carry a language tag: ```swift
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// Remove matching quotes around the whole reply.
    ///
    /// Skipped when the text contains the same quote character inside it, since
    /// then the outer pair is probably real punctuation rather than packaging.
    private static func strippingWrappingQuotes(_ text: String) -> String {
        let pairs: [(Character, Character)] = [
            ("\"", "\""), ("'", "'"), ("\u{201C}", "\u{201D}"), ("\u{2018}", "\u{2019}"),
        ]

        for (open, close) in pairs {
            guard text.count > 2, text.first == open, text.last == close else { continue }
            let inner = String(text.dropFirst().dropLast())
            guard !inner.contains(open), !inner.contains(close) else { continue }
            return inner
        }
        return text
    }
}
