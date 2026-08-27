import Foundation

/// What each question is trying to pin down.
///
/// The wizard stops once every trait that applies to this person has an answer.
/// That is the "enough questions" test: not a fixed count, but whether anything
/// is still unknown that would change how their rewrite reads.
public enum VoiceTrait: String, CaseIterable, Codable, Sendable {
    case context        // where they write
    case audience       // who reads it
    case formality      // how buttoned-up
    case sentenceLength
    case contractions
    case decoration     // emoji and exclamation marks
    case directness     // how they disagree
    case jargon         // technical vocabulary
    case verbosity      // shorter or same length
}

/// One answer someone can pick.
public struct VoiceOption: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let detail: String

    /// The sentence this answer contributes to the finished voice description.
    /// Empty means it adds nothing -- some answers are only used for routing.
    let phrase: String

    public init(id: String, label: String, detail: String, phrase: String) {
        self.id = id
        self.label = label
        self.detail = detail
        self.phrase = phrase
    }
}

/// One step of the wizard.
public struct VoiceQuestion: Identifiable, Sendable {
    public let id: String
    public let trait: VoiceTrait
    public let prompt: String
    public let help: String
    public let options: [VoiceOption]

    /// Whether this question is worth asking, given what is already answered.
    /// Anything inferable from earlier answers is skipped rather than asked.
    let applies: @Sendable ([String: String]) -> Bool

    public func option(_ id: String) -> VoiceOption? {
        options.first { $0.id == id }
    }
}

/// The adaptive question flow that builds someone's voice description.
public enum VoiceWizard {

    /// Hard ceiling. In practice the conditional skips land most people on six
    /// or seven -- a wizard that outstays its welcome does not get finished.
    public static let maxQuestions = 10

    // MARK: - The questions

    public static let all: [VoiceQuestion] = [

        VoiceQuestion(
            id: "context",
            trait: .context,
            prompt: "Where do you do most of your writing?",
            help: "This sets the baseline. A Slack message and a design doc want different rewrites.",
            options: [
                .init(id: "chat", label: "Chat",
                      detail: "Slack, Teams, Discord",
                      phrase: "I write mostly in chat -- Slack and similar."),
                .init(id: "email", label: "Email",
                      detail: "Work mail, replies, threads",
                      phrase: "I write mostly email."),
                .init(id: "docs", label: "Documents",
                      detail: "Specs, notes, long-form",
                      phrase: "I write mostly documents and long-form notes."),
                .init(id: "reviews", label: "Code review",
                      detail: "PR comments, issues, tickets",
                      phrase: "I write mostly pull request comments and issues."),
            ],
            applies: { _ in true }
        ),

        VoiceQuestion(
            id: "audience",
            trait: .audience,
            prompt: "Who usually reads it?",
            help: "Who you are writing to changes tone more than what you are writing about.",
            options: [
                .init(id: "teammates", label: "Teammates",
                      detail: "People you work with daily",
                      phrase: "Usually to teammates I know well."),
                .init(id: "customers", label: "Customers",
                      detail: "Clients, users, support",
                      phrase: "Usually to customers or users."),
                .init(id: "leadership", label: "Leadership",
                      detail: "Managers, execs, stakeholders",
                      phrase: "Usually to managers and stakeholders."),
                .init(id: "public", label: "Public",
                      detail: "Community, social, open source",
                      phrase: "Usually in public, where anyone might read it."),
            ],
            applies: { _ in true }
        ),

        VoiceQuestion(
            id: "formality",
            trait: .formality,
            prompt: "How formal should it sound?",
            help: "",
            options: [
                .init(id: "veryCasual", label: "Very casual",
                      detail: "Like talking to a friend",
                      phrase: "Keep it very casual, the way I would talk to a friend."),
                .init(id: "casual", label: "Casual",
                      detail: "Relaxed but competent",
                      phrase: "Keep it relaxed but competent -- casual, not sloppy."),
                .init(id: "neutral", label: "Neutral",
                      detail: "Plain and unfussy",
                      phrase: "Keep it plain and unfussy. Neither stiff nor chatty."),
                .init(id: "formal", label: "Formal",
                      detail: "Buttoned-up and precise",
                      phrase: "Keep it formal and precise."),
            ],
            applies: { _ in true }
        ),

        VoiceQuestion(
            id: "sentences",
            trait: .sentenceLength,
            prompt: "How do your sentences run?",
            help: "",
            options: [
                .init(id: "short", label: "Short and punchy",
                      detail: "One idea per sentence",
                      phrase: "Use short, punchy sentences. One idea each."),
                .init(id: "mixed", label: "Mixed",
                      detail: "Varied rhythm",
                      phrase: "Vary sentence length so it does not read like a list."),
                .init(id: "long", label: "Longer, flowing",
                      detail: "Connected clauses",
                      phrase: "Longer, flowing sentences are fine. Do not chop them up."),
            ],
            applies: { _ in true }
        ),

        VoiceQuestion(
            id: "contractions",
            trait: .contractions,
            prompt: "Contractions -- \"I'm\", \"don't\", \"we'll\"?",
            help: "",
            options: [
                .init(id: "always", label: "Always",
                      detail: "Sounds natural",
                      phrase: "Use contractions throughout."),
                .init(id: "sometimes", label: "Sometimes",
                      detail: "Where they read well",
                      phrase: "Use contractions where they read naturally."),
                .init(id: "never", label: "Never",
                      detail: "Write them out",
                      phrase: "Do not use contractions. Write words out in full."),
            ],
            // Both extremes of formality already answer this. Only the middle
            // is genuinely ambiguous, so only the middle gets asked.
            applies: { answers in
                let formality = answers["formality"]
                return formality == "casual" || formality == "neutral"
            }
        ),

        VoiceQuestion(
            id: "decoration",
            trait: .decoration,
            prompt: "Emoji and exclamation marks?",
            help: "",
            options: [
                .init(id: "never", label: "Never",
                      detail: "Neither, ever",
                      phrase: "No emoji and no exclamation marks."),
                .init(id: "sparingly", label: "Sparingly",
                      detail: "The occasional one",
                      phrase: "The occasional emoji or exclamation mark is fine, but sparingly."),
                .init(id: "freely", label: "Freely",
                      detail: "They are part of how I talk",
                      phrase: "Emoji and exclamation marks are part of how I write. Use them."),
            ],
            // Only a live question where they are plausible. Formal documents
            // for leadership have already answered it.
            applies: { answers in
                if answers["formality"] == "formal" { return false }
                let context = answers["context"]
                let audience = answers["audience"]
                return context == "chat" || audience == "teammates" || audience == "public"
            }
        ),

        VoiceQuestion(
            id: "directness",
            trait: .directness,
            prompt: "When you disagree or give feedback?",
            help: "This is the one people most often get wrong about themselves. Answer how you actually write, not how you would like to.",
            options: [
                .init(id: "blunt", label: "Very direct",
                      detail: "Say the thing",
                      phrase: "Be direct. Say the thing plainly, without softening it."),
                .init(id: "balanced", label: "Balanced",
                      detail: "Clear but considerate",
                      phrase: "Be clear but considerate. Direct without being blunt."),
                .init(id: "softened", label: "Softened",
                      detail: "Cushion it a little",
                      phrase: "Soften disagreement. Cushion the edges a little."),
            ],
            applies: { _ in true }
        ),

        VoiceQuestion(
            id: "jargon",
            trait: .jargon,
            prompt: "Technical language?",
            help: "",
            options: [
                .init(id: "plain", label: "Plain words",
                      detail: "Explain rather than name-drop",
                      phrase: "Prefer plain words over jargon. Explain rather than name-drop."),
                .init(id: "some", label: "Some",
                      detail: "Precise where it matters",
                      phrase: "Keep technical terms where they are the precise word, but do not pile them on."),
                .init(id: "heavy", label: "Heavy",
                      detail: "My readers know the terms",
                      phrase: "Technical vocabulary is fine. My readers know the terms."),
            ],
            applies: { _ in true }
        ),

        VoiceQuestion(
            id: "verbosity",
            trait: .verbosity,
            prompt: "Should the rewrite be shorter than what you wrote?",
            help: "",
            options: [
                .init(id: "muchShorter", label: "Much shorter",
                      detail: "I over-write and know it",
                      phrase: "Cut hard. I over-write, so make it noticeably shorter."),
                .init(id: "slightlyShorter", label: "A bit shorter",
                      detail: "Trim the padding",
                      phrase: "Trim padding and repetition, but do not gut it."),
                .init(id: "same", label: "About the same",
                      detail: "Fix it, do not shrink it",
                      phrase: "Keep roughly the original length. Fix the writing, do not shrink it."),
            ],
            applies: { _ in true }
        ),
    ]

    // MARK: - Flow

    /// The questions that apply given what has been answered so far.
    public static func applicable(given answers: [String: String]) -> [VoiceQuestion] {
        all.filter { $0.applies(answers) }
    }

    /// The next question to ask, or `nil` when there is nothing left worth
    /// asking -- which is the signal to stop and show the result.
    public static func next(given answers: [String: String]) -> VoiceQuestion? {
        guard answers.count < maxQuestions else { return nil }
        return applicable(given: answers).first { answers[$0.id] == nil }
    }

    /// How far along, for the progress indicator. The denominator moves as
    /// answers rule questions in and out, which is honest: the wizard genuinely
    /// does not know its own length until it is nearly done.
    public static func progress(given answers: [String: String]) -> (asked: Int, total: Int) {
        let total = min(maxQuestions, max(applicable(given: answers).count, answers.count))
        return (answers.count, total)
    }

    public static func isComplete(_ answers: [String: String]) -> Bool {
        next(given: answers) == nil && !answers.isEmpty
    }

    // MARK: - Result

    /// Turn the answers into the description that gets sent to the model.
    ///
    /// Plain first-person prose rather than a list of settings, because that is
    /// what the model reads best -- and because the user can then edit it by
    /// hand afterwards without learning a syntax.
    public static func describe(_ answers: [String: String]) -> String {
        var lines: [String] = []

        for question in all {
            guard let answerID = answers[question.id],
                  let option = question.option(answerID),
                  !option.phrase.isEmpty
            else { continue }
            lines.append(option.phrase)
        }

        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: " ")
    }
}
