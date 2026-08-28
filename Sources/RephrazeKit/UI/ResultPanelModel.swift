import SwiftUI

/// One row of the picker: a variant and however much of it has arrived.
public struct VariantSlot: Sendable, Equatable {
    public var text: String = ""
    public var isComplete = false
    public var error: String?

    public var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Only a finished variant may be applied. Pasting a half-streamed rewrite
    /// would put a truncated sentence into the user's text field.
    public var isChoosable: Bool { isComplete && hasText }
}

/// State of the floating picker.
@MainActor
public final class ResultPanelModel: ObservableObject {

    public enum State {
        case loading
        /// Variants arriving one at a time, from the parallel path.
        case streaming
        /// Everything arrived at once, from the single-call path.
        case ready(RephraseSet)
        /// One rewrite, in the user's own voice. No choice to make.
        case personal
        /// The list of languages, waiting for one to be picked. No network yet.
        case languages
        /// The message being written in the chosen language.
        case translating(TargetLanguage)
        /// A back-and-forth about the rewrite, once the user has added context.
        case chat
        case failed(String)
    }

    @Published public var state: State = .loading {
        didSet { onStateChange?() }
    }
    @Published public var appName: String = ""

    /// Fired after every state change, so the event tap can follow how many
    /// number keys are live.
    ///
    /// A `didSet` rather than a Combine subscription on `objectWillChange`:
    /// that fires *before* the change, so the tap would be told the old count,
    /// and the window where it is wrong is exactly the window in which the user
    /// is pressing the key.
    public var onStateChange: (() -> Void)?

    /// Per-variant progress for the streaming path.
    ///
    /// Always keyed by every variant and rendered in `allCases` order, so the
    /// number beside a row never changes as results land. A row that shifts
    /// under the user's finger between reading "2" and pressing it would apply
    /// the wrong rewrite.
    @Published public var slots: [RephraseVariant: VariantSlot] = [:]

    public private(set) var original: String = ""

    /// The single personalised rewrite, as it streams in.
    @Published public var personalText: String = ""
    @Published public var personalComplete = false

    /// The translation, as it streams in.
    @Published public var translationText: String = ""
    @Published public var translationComplete = false

    /// The state the language list was opened from.
    ///
    /// Kept so that esc can step back to it. Opening the list by mistake and
    /// having esc throw away four rewrites that already arrived would make the
    /// key feel dangerous, and it is pressed far too often for that.
    private var stateBeforeLanguages: State?

    /// The follow-up conversation, once the user has started one.
    @Published public var chat = Conversation(original: "")

    /// Text in the follow-up box at the bottom of the panel.
    @Published public var refineText: String = ""

    /// True while the panel holds keyboard focus for that box.
    ///
    /// The panel is otherwise deliberately focus-free, so this is the one state
    /// where the caret has left the user's own text field.
    @Published public var isEditing = false

    public var personalIsChoosable: Bool {
        personalComplete && !personalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The language currently being written in, if any.
    public var activeLanguage: TargetLanguage? {
        if case let .translating(language) = state { return language }
        return nil
    }

    public var translationIsChoosable: Bool {
        translationComplete
            && !translationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// How many number keys mean something right now.
    ///
    /// The event tap swallows exactly this many and lets every other key
    /// through, so typing "7" over a four-option picker still types a 7 rather
    /// than disappearing into a key that does nothing.
    public var liveDigitCount: Int {
        switch state {
        case .languages:            return TargetLanguage.allCases.count
        case .personal, .translating, .chat: return 1
        case .streaming:            return RephraseVariant.allCases.count
        case let .ready(set):       return set.available.count
        case .loading, .failed:     return 0
        }
    }

    /// Called when the user picks one.
    public var onChoose: ((RephraseVariant, String) -> Void)?
    /// Called when the user picks a language to write in.
    public var onChooseLanguage: ((TargetLanguage) -> Void)?
    /// Called when the user takes the translation.
    public var onChooseTranslation: ((String) -> Void)?
    /// Called when the user takes the single personalised rewrite.
    public var onChoosePersonal: ((String) -> Void)?
    /// Called when the user takes a rewrite out of the conversation.
    public var onChooseRefined: ((String) -> Void)?
    /// Called with a follow-up instruction, to rewrite again.
    public var onRefine: ((String) -> Void)?
    /// Called when the panel needs keyboard focus for its input box.
    public var onRequestEditing: (() -> Void)?
    /// Called when the user is done typing and wants their own field back.
    public var onRequestEndEditing: (() -> Void)?

    public init() {}

    // MARK: - Streaming path

    public func beginStreaming(original: String) {
        self.original = original
        chat = Conversation(original: original)
        slots = Dictionary(
            uniqueKeysWithValues: RephraseVariant.allCases.map { ($0, VariantSlot()) }
        )
        state = .streaming
    }

    public func append(_ delta: String, to variant: RephraseVariant) {
        slots[variant, default: VariantSlot()].text += delta
    }

    public func complete(_ variant: RephraseVariant) {
        var slot = slots[variant] ?? VariantSlot()
        slot.text = RewriteSanitizer.clean(slot.text)
        slot.isComplete = true
        slots[variant] = slot
    }

    public func fail(_ variant: RephraseVariant, message: String) {
        var slot = slots[variant] ?? VariantSlot()
        slot.error = message
        slot.isComplete = true
        slots[variant] = slot
    }

    /// True once every variant has either finished or failed.
    public var isSettled: Bool {
        RephraseVariant.allCases.allSatisfy { slots[$0]?.isComplete ?? false }
    }

    /// Nothing usable came back at all.
    public var isAllFailed: Bool {
        isSettled && !RephraseVariant.allCases.contains { slots[$0]?.isChoosable ?? false }
    }

    /// Changes whenever the panel's shape should visibly change.
    ///
    /// Drives the resize animation. Deliberately not derived from the streamed
    /// text: the panel should ease between kinds of content, not re-animate on
    /// every token that arrives.
    public var stateID: String {
        switch state {
        case .loading: return "loading"
        case .streaming: return "streaming"
        case .ready: return "ready"
        case .personal: return "personal"
        case .languages: return "languages"
        case let .translating(language): return "translating-\(language.rawValue)"
        // Keyed by turn count, not by the text: the panel should ease open as
        // each turn is added, not re-animate on every token that arrives.
        case .chat: return "chat-\(chat.turns.count)"
        case .failed: return "failed"
        }
    }

    // MARK: - Personal voice path

    public func beginPersonal(original: String) {
        self.original = original
        chat = Conversation(original: original)
        personalText = ""
        personalComplete = false
        state = .personal
    }

    public func appendPersonal(_ delta: String) {
        personalText += delta
    }

    public func completePersonal() {
        personalText = RewriteSanitizer.clean(personalText)
        personalComplete = true
    }

    // MARK: - Translation

    /// True while the language list is on screen.
    public var isChoosingLanguage: Bool {
        if case .languages = state { return true }
        return false
    }

    /// Show the language list. No request goes out until one is picked.
    public func showLanguages() {
        if case .languages = state { return }
        pinOriginal()
        stateBeforeLanguages = state
        state = .languages
    }

    /// Step back out of the language list, if that is where we are.
    ///
    /// Returns false when there was nothing to step back to, which is the
    /// caller's cue that esc meant "dismiss the panel" instead.
    @discardableResult
    public func closeLanguages() -> Bool {
        guard case .languages = state, let previous = stateBeforeLanguages else {
            return false
        }
        state = previous
        stateBeforeLanguages = nil
        return true
    }

    public func beginTranslating(into language: TargetLanguage) {
        pinOriginal()
        stateBeforeLanguages = nil
        translationText = ""
        translationComplete = false
        state = .translating(language)
    }

    /// Copy the original out of the state that is about to be replaced.
    ///
    /// The single-call path carries it inside `.ready`, not in `original`, so
    /// leaving it there would lose it the moment we switch states -- taking the
    /// "before" line out of the header and, worse, writing an empty original
    /// into the history record.
    private func pinOriginal() {
        original = currentOriginal
    }

    public func appendTranslation(_ delta: String) {
        translationText += delta
    }

    public func completeTranslation() {
        translationText = RewriteSanitizer.clean(translationText)
        translationComplete = true
    }

    /// Apply the translation.
    public func chooseTranslation() {
        guard translationIsChoosable else { return }
        onChooseTranslation?(translationText)
    }

    // MARK: - Follow-up conversation

    /// True while the transcript is on screen.
    public var isChatting: Bool {
        if case .chat = state { return true }
        return false
    }

    /// The one rewrite currently on screen, if there is exactly one.
    ///
    /// Four variants are not one answer, so the picker has nothing to carry
    /// into a conversation and it starts from the original instead. A
    /// translation is left out too: it is in another language, and seeding the
    /// exchange with it would have the model reading its own last reply in
    /// Japanese while being asked to rewrite English.
    private var currentRewrite: String? {
        switch state {
        case .personal: return personalIsChoosable ? personalText : nil
        default: return nil
        }
    }

    /// Send the user's context and open a reply for it.
    ///
    /// The first one starts the conversation, seeded with whatever they were
    /// looking at, so "shorter" means shorter than that rather than shorter
    /// than what they typed. Every later one continues it.
    public func ask(_ instruction: String) {
        if !isChatting {
            pinOriginal()
            chat = Conversation(original: original, opening: currentRewrite)
        }
        chat.ask(instruction)
        state = .chat
    }

    public func appendChat(_ delta: String) {
        chat.append(delta)
    }

    /// Finish the reply, and tell the tap that `1` now means something.
    ///
    /// `onStateChange` by hand because the state itself did not change -- it is
    /// still `.chat`. Without this the number key would stay dead until the
    /// next state change, which in a conversation may never come.
    public func completeChat() {
        chat.complete()
        onStateChange?()
    }

    public func failChat(_ message: String) {
        chat.fail(message)
        onStateChange?()
    }

    /// Apply the newest rewrite in the conversation.
    public func chooseChat() {
        guard let text = chat.latestRewrite else { return }
        onChooseRefined?(text)
    }

    /// Apply one particular reply, including a superseded one.
    ///
    /// Clicking back up the transcript is the only way to recover an answer the
    /// next instruction made worse, and without it the user would have to undo
    /// their own instruction by describing its opposite.
    public func choose(_ turn: ChatTurn) {
        guard turn.isChoosable else { return }
        onChooseRefined?(turn.text)
    }

    // MARK: - Follow-up instruction

    /// Ask for focus so the user can type an instruction.
    public func beginEditing() {
        guard !isEditing else { return }
        onRequestEditing?()
    }

    /// Give focus back to the text field the user was writing in.
    public func endEditing() {
        guard isEditing else { return }
        onRequestEndEditing?()
    }

    /// Send the typed instruction and rewrite again.
    public func submitRefinement() {
        let instruction = refineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        refineText = ""
        onRefine?(instruction)
    }

    // MARK: - Choosing

    /// Apply the single personalised rewrite.
    public func choosePersonal() {
        guard personalIsChoosable else { return }
        onChoosePersonal?(personalText)
    }

    public func choose(_ variant: RephraseVariant) {
        switch state {
        case .personal:
            choosePersonal()
        case .translating:
            chooseTranslation()
        case .chat:
            chooseChat()
        case .languages:
            break
        case .streaming:
            guard let slot = slots[variant], slot.isChoosable else { return }
            onChoose?(variant, slot.text)
        case let .ready(set):
            guard let text = set.variants[variant] else { return }
            onChoose?(variant, text)
        default:
            break
        }
    }

    /// Pick by number key.
    public func chooseByDigit(_ digit: Int) {
        switch state {
        case .personal:
            // Only one thing on screen, so only "1" means anything.
            guard digit == 1 else { return }
            choosePersonal()

        case .translating:
            guard digit == 1 else { return }
            chooseTranslation()

        case .chat:
            // Only the newest reply has a key. The rest are still one click
            // away, but numbering a growing transcript would move the keys
            // under the user's finger with every message.
            guard digit == 1 else { return }
            chooseChat()

        case .languages:
            // 1-9 then 0, matching the number row, so the tenth language sits
            // where the tenth key is.
            guard let language = TargetLanguage.forDigit(digit) else { return }
            onChooseLanguage?(language)
        case .streaming:
            // Fixed slots: digit N is always the Nth variant, arrived or not.
            guard digit >= 1, digit <= RephraseVariant.allCases.count else { return }
            choose(RephraseVariant.allCases[digit - 1])
        case let .ready(set):
            let options = set.available
            guard digit >= 1, digit <= options.count else { return }
            let option = options[digit - 1]
            onChoose?(option.variant, option.text)
        default:
            break
        }
    }

    /// Original text behind whatever is on screen, for the history record.
    public var currentOriginal: String {
        if case let .ready(set) = state { return set.original }
        return original
    }
}
