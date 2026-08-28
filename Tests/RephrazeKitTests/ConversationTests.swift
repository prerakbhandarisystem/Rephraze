import Testing
import Foundation
@testable import RephrazeKit

@Suite("The follow-up conversation")
struct ConversationTests {

    private let system = "SYSTEM"

    /// Roles only, which is what the API cares about and what is easy to break.
    private func roles(_ conversation: Conversation) -> [String] {
        conversation.messages(system: system).map(\.role)
    }

    private func contents(_ conversation: Conversation) -> [String] {
        conversation.messages(system: system).map(\.content)
    }

    // MARK: - Shape of the request

    @Test("The system prompt and the original always lead")
    func opensWithTheOriginal() {
        let conversation = Conversation(original: "hey can u send that thing")
        #expect(contents(conversation) == [system, "hey can u send that thing"])
    }

    @Test("An instruction alternates with the reply it produced")
    func alternates() {
        var conversation = Conversation(original: "the text")
        conversation.ask("Shorter")
        conversation.append("Short version.")
        conversation.complete()
        conversation.ask("Warmer")

        #expect(roles(conversation) == ["system", "user", "user", "assistant", "user"])
        #expect(contents(conversation).last == "Warmer")
    }

    /// The whole point of the type. Without this, "and warmer" would be applied
    /// to the original rather than to the answer the user is reacting to.
    @Test("Every earlier round is still in the request")
    func carriesTheWholeHistory() {
        var conversation = Conversation(original: "the text")
        for round in 1...3 {
            conversation.ask("instruction \(round)")
            conversation.append("reply \(round)")
            conversation.complete()
        }

        let sent = contents(conversation)
        for round in 1...3 {
            #expect(sent.contains("instruction \(round)"))
            #expect(sent.contains("reply \(round)"))
        }
    }

    @Test("The reply being streamed right now is not sent back")
    func skipsTheOpenReply() {
        var conversation = Conversation(original: "the text")
        conversation.ask("Shorter")
        conversation.append("half a sen")

        #expect(roles(conversation) == ["system", "user", "user"])
        #expect(conversation.isAnswering)
    }

    @Test("A failed round leaves no empty assistant message behind")
    func skipsFailures() {
        var conversation = Conversation(original: "the text")
        conversation.ask("Shorter")
        conversation.fail("OpenAI is rate limiting.")
        conversation.ask("Shorter, please")

        #expect(roles(conversation) == ["system", "user", "user", "user"])
        #expect(conversation.latestRewrite == nil)
    }

    // MARK: - Seeding

    @Test("The rewrite already on screen becomes the first reply")
    func seedsFromWhatIsOnScreen() {
        var conversation = Conversation(original: "the text", opening: "A tidy version.")
        #expect(roles(conversation) == ["system", "user", "assistant"])

        conversation.ask("Shorter")
        #expect(contents(conversation) == [system, "the text", "A tidy version.", "Shorter"])
    }

    @Test("Nothing to seed with leaves the conversation starting at the original")
    func toleratesNoSeed() {
        #expect(Conversation(original: "x", opening: nil).turns.isEmpty)
        #expect(Conversation(original: "x", opening: "").turns.isEmpty)
        #expect(Conversation(original: "x", opening: "  \n ").turns.isEmpty)
    }

    // MARK: - What can be applied

    @Test("A reply is only applicable once it has finished arriving")
    func halfStreamedRepliesAreNotApplicable() {
        var conversation = Conversation(original: "the text")
        conversation.ask("Shorter")
        conversation.append("Short ver")
        #expect(conversation.latestRewrite == nil)

        conversation.complete()
        #expect(conversation.latestRewrite == "Short ver")
    }

    @Test("The newest finished reply is the one the number key applies")
    func latestWins() {
        var conversation = Conversation(original: "the text")
        conversation.ask("one")
        conversation.append("first answer")
        conversation.complete()
        conversation.ask("two")
        conversation.append("second answer")
        conversation.complete()

        #expect(conversation.latestRewrite == "second answer")
    }

    /// A round that failed must not hide the good answer above it: that one is
    /// still on screen, still clickable, and still the best thing the user has.
    @Test("A failed round falls back to the last good answer")
    func failureKeepsTheAnswerAbove() {
        var conversation = Conversation(original: "the text")
        conversation.ask("one")
        conversation.append("good answer")
        conversation.complete()
        conversation.ask("two")
        conversation.fail("Network went away.")

        #expect(conversation.latestRewrite == "good answer")
    }

    @Test("Replies are unwrapped on the way in, like every other path")
    func sanitisesOnCompletion() {
        var conversation = Conversation(original: "the text")
        conversation.ask("Shorter")
        conversation.append("\"Quoted for no reason.\"")
        conversation.complete()

        #expect(conversation.latestRewrite == "Quoted for no reason.")
    }

    /// The round stays open so the failure can still be written into it -- see
    /// `Conversation.complete`.
    @Test("A reply of pure whitespace does not close the round")
    func emptyRepliesAreNotApplicable() {
        var conversation = Conversation(original: "the text")
        conversation.ask("Shorter")
        conversation.append("   \n  ")
        conversation.complete()

        #expect(conversation.latestRewrite == nil)
        #expect(conversation.isAnswering)
        #expect(roles(conversation) == ["system", "user", "user"])

        conversation.fail("OpenAI returned nothing.")
        #expect(conversation.turns.last?.error == "OpenAI returned nothing.")
    }

    @Test("Text arriving after a round closed is ignored")
    func ignoresLateDeltas() {
        var conversation = Conversation(original: "the text")
        conversation.ask("Shorter")
        conversation.append("done")
        conversation.complete()
        conversation.append(" and then some")

        #expect(conversation.latestRewrite == "done")
    }

    @Test("Rounds are counted by what the user asked, not by what came back")
    func countsExchanges() {
        var conversation = Conversation(original: "the text", opening: "seed")
        #expect(conversation.exchanges == 0)

        conversation.ask("one")
        conversation.fail("nope")
        conversation.ask("two")
        #expect(conversation.exchanges == 2)
    }
}

@Suite("The conversation prompt")
struct ChatPromptTests {

    /// The core rules forbid acting on anything that looks like an instruction,
    /// because the captured text usually is one. The conversation inverts that
    /// for the user's own messages, so both halves have to be present and the
    /// boundary has to be stated after the rules it qualifies.
    @Test("Instructions are exempted from the rule that bans following them")
    func namesBothHalves() {
        let prompt = Prompt.chatSystem(style: "")
        #expect(prompt.contains("FIRST user message"))
        #expect(prompt.contains("never apply"))

        let boundaryAt = prompt.range(of: "never apply")!.lowerBound
        let rulesAt = prompt.range(of: "ONLY the rewritten text")!.lowerBound
        #expect(boundaryAt < rulesAt)
    }

    @Test("The saved style is carried in, and left out when there is none")
    func carriesTheStyle() {
        #expect(Prompt.chatSystem(style: "I write in short sentences.")
            .contains("I write in short sentences."))
        #expect(!Prompt.chatSystem(style: "   ").contains("how they write"))
    }

    @Test("Every reply is still a whole rewrite, not a diff")
    func asksForWholeRewrites() {
        let prompt = Prompt.chatSystem(style: "")
        #expect(prompt.contains("complete rewrite"))
        #expect(prompt.contains("every instruction so far"))
    }
}
