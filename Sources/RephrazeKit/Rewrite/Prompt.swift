import Foundation

/// What we ask the model to do.
public enum Prompt {

    /// Rules, in rough priority order:
    ///
    /// - Return *only* the rewrite. Anything else gets pasted into the user's
    ///   text box verbatim, so a preamble like "Sure! Here's a better version:"
    ///   would be a bug, not a pleasantry.
    /// - Preserve `@mentions`, URLs and emoji shortcodes exactly. Slack cannot
    ///   re-link a mention we mangled, so at minimum the characters must survive.
    /// - Match the original register. Rewriting a casual Slack message into
    ///   business English is not an improvement.
    public static let system = """
        You rewrite text to be clearer and better written.

        Rules:
        - Reply with ONLY the rewritten text. No preamble, no explanation, no \
        quotation marks around it, no alternatives.
        - Keep the original meaning exactly. Do not add facts, opinions, or detail.
        - Keep the original language, tone and level of formality. Casual stays \
        casual.
        - Keep roughly the original length. Do not pad it out.
        - Reproduce these EXACTLY as they appear: @mentions, #channels, URLs, \
        email addresses, file paths, code, and :emoji_shortcodes:.
        - Preserve the existing line breaks and list structure.
        - If the text is already well written, return it unchanged.
        """

    public static func user(_ text: String) -> String {
        text
    }

    // MARK: - Four variants in one call

    /// One request returns all four rewrites as JSON.
    ///
    /// Four separate calls would cost four times as much and could half-fail,
    /// leaving the panel with gaps. One structured response either works or
    /// does not.
    public static var variantsSystem: String {
        let menu = RephraseVariant.allCases
            .map { "- \"\($0.rawValue)\": \($0.instruction)" }
            .joined(separator: "\n")

        return """
            You rewrite text four different ways.

            Return a JSON object with exactly these four keys:
            \(menu)

            Rules for every variant:
            - Keep the original meaning. Do not add facts, opinions or detail.
            - Keep the original language.
            - Reproduce these EXACTLY: @mentions, #channels, URLs, email \
            addresses, file paths, code, and :emoji_shortcodes:.
            - Preserve line breaks and list structure.
            - No preamble, no explanation, no quotation marks wrapped around \
            the text. The value is the rewritten text and nothing else.
            - Every variant must be genuinely different from the others.
            """
    }
}
