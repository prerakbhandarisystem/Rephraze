import Foundation

/// Text arriving from the model, in whatever state it has reached so far.
///
/// Every path in this app tells the same three-step story: text arrives a piece
/// at a time, it finishes or it fails, and only once it has finished may it be
/// pasted into someone's text field. The four tones, the styled rewrite, a
/// translation and each reply in a conversation are all that same story.
///
/// It used to be written out once per path, which meant the rule about what
/// counts as safe to paste lived in four places, and a change to it had four
/// chances to miss one. Now there is one copy and the paths differ only in what
/// they wrap around it.
public struct Streamed: Sendable, Equatable {

    public var text: String = ""
    public var isComplete = false
    public var error: String?

    public init(text: String = "", isComplete: Bool = false, error: String? = nil) {
        self.text = text
        self.isComplete = isComplete
        self.error = error
    }

    public var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether this may be applied to the user's text field.
    ///
    /// Half-streamed text would paste a truncated sentence; failed or empty
    /// text would paste nothing at all over something they wrote.
    public var isChoosable: Bool { isComplete && error == nil && hasText }

    public mutating func append(_ delta: String) {
        guard !isComplete else { return }
        text += delta
    }

    /// Close it off, unwrapping whatever packaging the model added.
    public mutating func complete() {
        guard !isComplete else { return }
        text = RewriteSanitizer.clean(text)
        isComplete = true
    }

    /// Record why nothing usable arrived.
    ///
    /// Allowed to overwrite a round that closed with nothing in it -- a stream
    /// that produced only whitespace completes empty, and the caller's "did
    /// anything arrive?" check then needs somewhere to put the reason. Text
    /// that is actually usable is never overwritten.
    public mutating func fail(_ message: String) {
        guard !isChoosable else { return }
        error = message
        isComplete = true
    }
}
