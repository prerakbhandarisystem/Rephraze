import Foundation

/// Answers, keyed by question id. A list because some questions take more than
/// one answer -- most people write in several places, for several audiences.
public typealias VoiceAnswers = [String: [String]]

/// One answer someone can pick.
public struct VoiceOption: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let detail: String

    /// Complete sentence, used when this is the only answer to its question.
    let phrase: String

    /// Noun phrase, used when the question takes several answers and they get
    /// joined into one sentence. Empty means `phrase` is used instead.
    let fragment: String

    public init(
        id: String,
        label: String,
        detail: String,
        phrase: String,
        fragment: String = ""
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.phrase = phrase
        self.fragment = fragment
    }
}

/// One step of the wizard.
public struct VoiceQuestion: Identifiable, Sendable {
    public let id: String
    public let prompt: String
    public let help: String
    public let options: [VoiceOption]

    /// Whether several answers may be chosen.
    ///
    /// True only where several are genuinely compatible. "Where do you write?"
    /// can be chat *and* email; "how formal?" cannot be casual *and* formal,
    /// and offering that would produce a self-contradicting instruction.
    public let allowsMultiple: Bool

    /// Sentence opener for the multi-answer case: "I write mostly in ".
    let lead: String

    /// Whether this question is worth asking, given what is already answered.
    /// Anything inferable from earlier answers is skipped rather than asked.
    let applies: @Sendable (VoiceAnswers) -> Bool

    public func option(_ id: String) -> VoiceOption? {
        options.first { $0.id == id }
    }

    init(
        id: String,
        prompt: String,
        help: String,
        options: [VoiceOption],
        allowsMultiple: Bool = false,
        lead: String = "",
        applies: @escaping @Sendable (VoiceAnswers) -> Bool
    ) {
        self.id = id
        self.prompt = prompt
        self.help = help
        self.options = options
        self.allowsMultiple = allowsMultiple
        self.lead = lead
        self.applies = applies
    }
}

/// The adaptive question flow that builds someone's writing style description.
///
/// It stops when no applicable question is still unanswered -- not at a fixed
/// count. Questions rule themselves out based on earlier answers, so someone
/// who writes formally is never asked about emoji.
public enum VoiceWizard {

    /// Hard ceiling. In practice the conditional skips land most people on six
    /// or seven -- a wizard that outstays its welcome does not get finished.
    public static let maxQuestions = 10

    /// Single-answer questions read cleanly as `answers[id]?.first`.
    static func choice(_ answers: VoiceAnswers, _ questionID: String) -> String? {
        answers[questionID]?.first
    }

    static func chose(_ answers: VoiceAnswers, _ questionID: String, _ optionID: String) -> Bool {
        answers[questionID]?.contains(optionID) ?? false
    }

    // MARK: - The questions

    public static let all: [VoiceQuestion] = [

        VoiceQuestion(
            id: "context",
            prompt: "Where do you do most of your writing?",
            help: "Pick as many as apply.",
            options: [
                .init(id: "chat", label: "Chat",
                      detail: "Slack, Teams, Discord",
                      phrase: "I write mostly in chat -- Slack and similar.",
                      fragment: "chat like Slack"),
                .init(id: "email", label: "Email",
                      detail: "Work mail, replies, threads",
                      phrase: "I write mostly email.",
                      fragment: "email"),
                .init(id: "docs", label: "Documents",
                      detail: "Specs, notes, long-form",
                      phrase: "I write mostly documents and long-form notes.",
                      fragment: "documents and long-form notes"),
                .init(id: "reviews", label: "Code review",
                      detail: "PR comments, issues, tickets",
                      phrase: "I write mostly pull request comments and issues.",
                      fragment: "pull request comments and issues"),
            ],
            allowsMultiple: true,
            lead: "I write mostly in ",
            applies: { _ in true }
        ),

        VoiceQuestion(
            id: "audience",
            prompt: "Who usually reads it?",
            help: "Pick as many as apply. Who you write to changes tone more than what you write about.",
            options: [
                .init(id: "teammates", label: "Teammates",
                      detail: "People you work with daily",
                      phrase: "Usually to teammates I know well.",
                      fragment: "teammates I know well"),
                .init(id: "customers", label: "Customers",
                      detail: "Clients, users, support",
                      phrase: "Usually to customers or users.",
                      fragment: "customers and users"),
                .init(id: "leadership", label: "Leadership",
                      detail: "Managers, execs, stakeholders",
                      phrase: "Usually to managers and stakeholders.",
                      fragment: "managers and stakeholders"),
                .init(id: "public", label: "Public",
                      detail: "Community, social, open source",
                      phrase: "Usually in public, where anyone might read it.",
                      fragment: "a public audience"),
            ],
            allowsMultiple: true,
            lead: "Usually writing to ",
            applies: { _ in true }
        ),

        VoiceQuestion(
            id: "formality",
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
                let formality = choice(answers, "formality")
                return formality == "casual" || formality == "neutral"
            }
        ),

        VoiceQuestion(
            id: "decoration",
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
            // Only a live question where they are plausible. Formal writing for
            // leadership has already answered it.
            applies: { answers in
                if choice(answers, "formality") == "formal" { return false }
                return chose(answers, "context", "chat")
                    || chose(answers, "audience", "teammates")
                    || chose(answers, "audience", "public")
            }
        ),

        VoiceQuestion(
            id: "directness",
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
    public static func applicable(given answers: VoiceAnswers) -> [VoiceQuestion] {
        all.filter { $0.applies(answers) }
    }

    /// The next question to ask, or `nil` when there is nothing left worth
    /// asking -- which is the signal to stop and show the result.
    public static func next(given answers: VoiceAnswers) -> VoiceQuestion? {
        guard answers.count < maxQuestions else { return nil }
        return applicable(given: answers).first { (answers[$0.id] ?? []).isEmpty }
    }

    /// How far along, for the progress indicator. The denominator moves as
    /// answers rule questions in and out, which is honest: the wizard genuinely
    /// does not know its own length until it is nearly done.
    public static func progress(given answers: VoiceAnswers) -> (asked: Int, total: Int) {
        let answered = answers.filter { !$0.value.isEmpty }.count
        let total = min(maxQuestions, max(applicable(given: answers).count, answered))
        return (answered, total)
    }

    public static func isComplete(_ answers: VoiceAnswers) -> Bool {
        next(given: answers) == nil && !answers.isEmpty
    }

    /// Strip answers to questions that no longer apply, so a retracted branch
    /// cannot leave a stale phrase in the description.
    public static func pruned(_ answers: VoiceAnswers) -> VoiceAnswers {
        let allowed = Set(applicable(given: answers).map(\.id))
        return answers.filter { allowed.contains($0.key) && !$0.value.isEmpty }
    }

    // MARK: - Result

    /// Turn the answers into the description that gets sent to the model.
    ///
    /// Plain first-person prose rather than a list of settings, because that is
    /// what the model reads best -- and because the user can then edit it by
    /// hand afterwards without learning a syntax.
    public static func describe(_ answers: VoiceAnswers) -> String {
        var lines: [String] = []

        for question in all {
            let selected = (answers[question.id] ?? [])
                .compactMap { question.option($0) }
            guard !selected.isEmpty else { continue }

            if question.allowsMultiple && selected.count > 1 {
                let fragments = selected.map { $0.fragment.isEmpty ? $0.label : $0.fragment }
                lines.append(question.lead + list(fragments) + ".")
            } else if let only = selected.first, !only.phrase.isEmpty {
                lines.append(only.phrase)
            }
        }

        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: " ")
    }

    /// "a, b and c"
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
