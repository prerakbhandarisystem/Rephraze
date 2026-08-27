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
    /// Kept as the fallback path behind `Settings.useParallelVariants`. It is
    /// cheaper by roughly a fifth, but nothing appears until every variant is
    /// written -- see `singleVariantSystem` for the version that trades that
    /// for speed.
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

    // MARK: - One variant per call

    /// System prompt for a single variant, used by the parallel path.
    ///
    /// Deliberately not the four-key prompt with three keys removed: naming one
    /// job keeps the model from hedging toward the others, and it is ~100
    /// tokens shorter, which is what keeps four calls close to the cost of one.
    public static func singleVariantSystem(for variant: RephraseVariant) -> String {
        """
        You rewrite text. \(variant.instruction)

        Rules:
        - Reply with ONLY the rewritten text. No preamble, no explanation, no \
        quotation marks around it, no alternatives.
        - Keep the original meaning. Do not add facts, opinions or detail.
        - Keep the original language.
        - Reproduce these EXACTLY: @mentions, #channels, URLs, email \
        addresses, file paths, code, and :emoji_shortcodes:.
        - Preserve the existing line breaks and list structure.
        """
    }

    // MARK: - Your voice

    /// One rewrite, in the user's own described voice.
    ///
    /// Their description goes in the middle, and the structural rules come
    /// after it. That ordering is deliberate: whatever someone writes about
    /// their voice, the rewrite still has to be only the text, still has to
    /// keep their @mentions intact, and still must not invent facts. Those
    /// rules are what make it safe to paste straight back into their app, so
    /// they get the last word.
    public static func personalSystem(style: String) -> String {
        let described = style.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
            You rewrite text so that it sounds like one specific person.

            This is how they describe their own voice:
            \"\"\"
            \(described)
            \"\"\"

            Rewrite the text to match that voice as closely as you can.

            These rules always apply, even if the description above suggests \
            otherwise:
            - Reply with ONLY the rewritten text. No preamble, no explanation, \
            no quotation marks around it, no alternatives, no commentary on \
            the voice.
            - Keep the original meaning. Do not add facts, opinions or detail \
            that were not there.
            - Keep the original language.
            - Reproduce these EXACTLY: @mentions, #channels, URLs, email \
            addresses, file paths, code, and :emoji_shortcodes:.
            - Preserve the existing line breaks and list structure.
            """
    }
}
