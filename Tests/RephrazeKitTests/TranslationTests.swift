import Testing
import Foundation
@testable import RephrazeKit

@Suite("Target languages")
struct TargetLanguageTests {

    @Test("Ten languages, ten keys, no collisions")
    func digitsAreUnique() {
        let digits = TargetLanguage.allCases.map(\.shortcutDigit)
        #expect(digits.count == 10)
        #expect(Set(digits).count == 10)
    }

    @Test("Numbered 1-9 then 0, matching the number row")
    func digitOrder() {
        #expect(TargetLanguage.allCases.map(\.shortcutDigit) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
        #expect(TargetLanguage.english.shortcutDigit == 1)
        #expect(TargetLanguage.japanese.shortcutDigit == 0)
    }

    @Test("Every digit maps back to the language that shows it")
    func digitsRoundTrip() {
        for language in TargetLanguage.allCases {
            #expect(TargetLanguage.forDigit(language.shortcutDigit) == language)
        }
    }

    @Test("Keys outside the row select nothing")
    func unknownDigit() {
        #expect(TargetLanguage.forDigit(11) == nil)
        #expect(TargetLanguage.forDigit(-1) == nil)
    }

    @Test("The three languages with varieties pin one for the model")
    func varietiesArePinned() {
        // Left to the model, these come back as a coin flip between variants
        // that are not mutually acceptable to their readers.
        #expect(TargetLanguage.chinese.promptName.contains("Simplified"))
        #expect(TargetLanguage.portuguese.promptName.contains("Brazilian"))
        #expect(TargetLanguage.arabic.promptName.contains("Modern Standard"))
    }

    @Test("Arabic is the one that needs right-to-left layout")
    func rightToLeft() {
        #expect(TargetLanguage.arabic.isRightToLeft)
        #expect(TargetLanguage.allCases.filter(\.isRightToLeft) == [.arabic])
    }
}

@Suite("Translation prompt")
struct TranslationPromptTests {

    @Test("Names the target language")
    func namesTheLanguage() {
        let prompt = Prompt.translateSystem(to: .japanese)
        #expect(prompt.contains("Japanese"))
    }

    @Test("Drops the rule that keeps the input's language")
    func replacesTheLanguageRule() {
        // The rewriting paths all say this. The translation path is defined by
        // being the one that does not.
        #expect(Prompt.coreRules.contains("Keep the original language"))
        #expect(!Prompt.translateSystem(to: .german).contains("Keep the original language"))
    }

    @Test("Forbids going via another language on the way")
    func noIntermediateLanguage() {
        let prompt = Prompt.translateSystem(to: .hindi)
        #expect(prompt.contains("Compose it directly"))
        #expect(prompt.contains("no English draft"))
    }

    @Test("Keeps the rules that make output safe to paste")
    func keepsCoreRules() {
        // Translation must not be a prompt of its own that drifts away from the
        // guarantees every other path gives.
        for language in TargetLanguage.allCases {
            let prompt = Prompt.translateSystem(to: language)
            #expect(prompt.contains("Reply with ONLY the rewritten text"))
            #expect(prompt.contains(":emoji_shortcodes:"))
            #expect(prompt.contains("never as a question to answer"))
        }
    }
}

@Suite("Translation token budget")
struct TranslationBudgetTests {

    @Test("Roomier than a rewrite of the same text")
    func widerThanRewrite() {
        let text = String(repeating: "a", count: 4000)
        #expect(OpenAIClient.translationBudget(for: text)
                    > OpenAIClient.tokenBudget(for: text))
    }

    @Test("Still capped, so a runaway response cannot stream forever")
    func ceiling() {
        let text = String(repeating: "a", count: 100_000)
        #expect(OpenAIClient.translationBudget(for: text) == 4096)
    }
}

@MainActor
@Suite("Language picker state")
struct LanguagePickerTests {

    private func streamingModel() -> ResultPanelModel {
        let model = ResultPanelModel()
        model.beginStreaming(original: "can we move the call?")
        return model
    }

    @Test("esc steps back to the rewrites instead of throwing them away")
    func closingReturnsToPreviousState() {
        let model = streamingModel()
        model.append("Could we move the call?", to: .polished)

        model.showLanguages()
        #expect(model.liveDigitCount == 10)

        #expect(model.closeLanguages())
        if case .streaming = model.state {} else {
            Issue.record("Expected to land back on the rewrites")
        }
        // The rewrite that had already arrived is still there.
        #expect(model.slots[.polished]?.text == "Could we move the call?")
    }

    @Test("Nothing to step back to reports so, and esc means dismiss")
    func closingFromElsewhere() {
        let model = streamingModel()
        #expect(!model.closeLanguages())
    }

    @Test("Opening the list twice does not lose where it came from")
    func showingIsIdempotent() {
        let model = streamingModel()
        model.showLanguages()
        model.showLanguages()

        #expect(model.closeLanguages())
        if case .streaming = model.state {} else {
            Issue.record("Second show overwrote the state to return to")
        }
    }

    @Test("0 picks the tenth language")
    func zeroPicksTheTenth() {
        let model = streamingModel()
        var chosen: TargetLanguage?
        model.onChooseLanguage = { chosen = $0 }

        model.showLanguages()
        model.chooseByDigit(0)
        #expect(chosen == .japanese)
    }

    @Test("Every key on the row picks its language")
    func everyDigitPicks() {
        for language in TargetLanguage.allCases {
            let model = streamingModel()
            var chosen: TargetLanguage?
            model.onChooseLanguage = { chosen = $0 }

            model.showLanguages()
            model.chooseByDigit(language.shortcutDigit)
            #expect(chosen == language)
        }
    }
}

@MainActor
@Suite("Translation state")
struct TranslationStateTests {

    @Test("A half-streamed translation cannot be applied")
    func incompleteIsNotChoosable() {
        let model = ResultPanelModel()
        model.beginStreaming(original: "hello")
        model.beginTranslating(into: .spanish)
        model.appendTranslation("Hola, ¿podemos")

        #expect(!model.translationIsChoosable)
        #expect(model.activeLanguage == .spanish)

        model.completeTranslation()
        #expect(model.translationIsChoosable)
    }

    @Test("Only 1 applies it -- there is nothing else on screen")
    func onlyOneApplies() {
        let model = ResultPanelModel()
        model.beginTranslating(into: .french)
        model.appendTranslation("Bonjour")
        model.completeTranslation()

        var applied: String?
        model.onChooseTranslation = { applied = $0 }

        model.chooseByDigit(2)
        #expect(applied == nil)

        model.chooseByDigit(1)
        #expect(applied == "Bonjour")
        #expect(model.liveDigitCount == 1)
    }

    @Test("Packaging the model slipped in is stripped before it is applied")
    func sanitised() {
        let model = ResultPanelModel()
        model.beginTranslating(into: .german)
        model.appendTranslation("\"Können wir den Termin verschieben?\"")
        model.completeTranslation()

        #expect(model.translationText == "Können wir den Termin verschieben?")
    }

    @Test("The original survives a translation started from the single-call path")
    func originalSurvivesFromReady() {
        // That path carries the original inside `.ready` rather than in
        // `original`, and `.ready` is exactly what translating replaces. Losing
        // it here would blank the "before" line and write an empty original
        // into the history record.
        let model = ResultPanelModel()
        model.state = .ready(
            RephraseSet(original: "shall we push the call?",
                        variants: [.polished: "Shall we move the call?"])
        )

        model.showLanguages()
        #expect(model.isChoosingLanguage)
        #expect(model.currentOriginal == "shall we push the call?")

        model.beginTranslating(into: .hindi)
        #expect(!model.isChoosingLanguage)
        #expect(model.currentOriginal == "shall we push the call?")
    }

    @Test("Every state change reports the live digit count")
    func stateChangesAreReported() {
        // This is what keeps the event tap swallowing the right keys. If it
        // lags, a key press lands on the wrong picker.
        let model = ResultPanelModel()
        var counts: [Int] = []
        model.onStateChange = { counts.append(model.liveDigitCount) }

        model.beginStreaming(original: "hi")
        model.showLanguages()
        model.beginTranslating(into: .french)

        #expect(counts == [4, 10, 1])
    }

    @Test("Switching language starts the new one from empty")
    func switchingClears() {
        let model = ResultPanelModel()
        model.beginTranslating(into: .russian)
        model.appendTranslation("Привет")
        model.completeTranslation()

        model.beginTranslating(into: .arabic)
        #expect(model.translationText.isEmpty)
        #expect(!model.translationComplete)
        #expect(model.activeLanguage == .arabic)
    }
}
