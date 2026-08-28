import Foundation

/// One message as the chat endpoint wants it.
///
/// A named type rather than a dictionary literal at each call site: the two
/// keys are easy to misspell and the compiler cannot tell you when you have,
/// because `[String: Any]` accepts anything.
public struct ChatMessage: Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    var payload: [String: String] { ["role": role, "content": content] }
}

/// One turn in the conversation about a piece of text.
///
/// The user's own turns are complete the moment they are made; only a reply
/// actually streams. Both are `Streamed` regardless, so the transcript is one
/// list of one kind of thing rather than two that have to be zipped together.
public struct ChatTurn: Identifiable, Sendable, Equatable {

    public enum Speaker: Sendable {
        /// Context or an instruction, typed by the user.
        case you
        /// A rewrite that takes everything said so far into account.
        case rephraze
    }

    public let id = UUID()
    public let speaker: Speaker
    public var content: Streamed

    public var text: String { content.text }
    public var isComplete: Bool { content.isComplete }
    public var error: String? { content.error }
    public var hasText: Bool { content.hasText }

    /// What the user typed is never something to paste back at them.
    public var isChoosable: Bool { speaker == .rephraze && content.isChoosable }
}

/// The running exchange about one captured piece of text.
///
/// ## Why the whole history goes back up every time
/// The obvious cheaper design is to fold each new instruction into the prompt
/// and rewrite the original again. It reads the same and behaves quite
/// differently: "and a bit warmer" then means warmer than what the user
/// originally typed, so the previous reply -- the thing they are actually
/// looking at and reacting to -- is thrown away and rebuilt from scratch. Each
/// message would jump somewhere new instead of converging.
///
/// So the conversation is the state: original, instruction, reply, instruction,
/// reply. The model can see what it last said, and "shorter" means shorter than
/// that.
///
/// Deliberately a plain value type with no reference to the UI or the network,
/// so the shape of what gets sent is unit-testable off the main actor.
public struct Conversation: Sendable, Equatable {

    /// The text the user captured. Always the first message, never edited.
    public let original: String
    public private(set) var turns: [ChatTurn] = []

    /// - Parameter opening: the rewrite already on screen when the conversation
    ///   started, if there was exactly one. Carrying it in as the first reply is
    ///   what makes the user's first instruction mean "change what I am reading"
    ///   rather than "change what I typed".
    public init(original: String, opening: String? = nil) {
        self.original = original
        if let opening, !opening.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            turns.append(
                ChatTurn(speaker: .rephraze, content: Streamed(text: opening, isComplete: true))
            )
        }
    }

    /// How many times the user has asked for something. For the log only.
    public var exchanges: Int {
        turns.filter { $0.speaker == .you }.count
    }

    /// Add the user's instruction, and open an empty reply for it to stream into.
    public mutating func ask(_ instruction: String) {
        turns.append(
            ChatTurn(speaker: .you, content: Streamed(text: instruction, isComplete: true))
        )
        turns.append(ChatTurn(speaker: .rephraze, content: Streamed()))
    }

    /// More of the reply currently being written.
    public mutating func append(_ delta: String) {
        guard let last = turns.indices.last else { return }
        turns[last].content.append(delta)
    }

    /// Close the reply currently being written.
    public mutating func complete() {
        guard let last = turns.indices.last else { return }
        turns[last].content.complete()
    }

    /// This reply failed. The rest of the conversation survives it, so one bad
    /// round does not cost the user a transcript they may still want to apply
    /// an earlier answer from.
    public mutating func fail(_ message: String) {
        guard let last = turns.indices.last else { return }
        turns[last].content.fail(message)
    }

    /// True while a reply is still arriving.
    public var isAnswering: Bool {
        turns.last.map { !$0.isComplete } ?? false
    }

    /// The newest finished rewrite -- the one the `1` key applies.
    public var latestRewrite: String? {
        turns.reversed().first(where: \.isChoosable)?.text
    }

    /// The exchange as the endpoint wants it, oldest first.
    ///
    /// Skips anything with nothing in it: the reply being streamed into right
    /// now is empty by construction, and a failed one has only an error, which
    /// would teach the model that empty answers are a thing it may give.
    public func messages(system: String) -> [ChatMessage] {
        var messages = [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: original),
        ]

        for turn in turns where turn.isComplete && turn.hasText && turn.error == nil {
            messages.append(
                ChatMessage(
                    role: turn.speaker == .you ? "user" : "assistant",
                    content: turn.text
                )
            )
        }
        return messages
    }
}
