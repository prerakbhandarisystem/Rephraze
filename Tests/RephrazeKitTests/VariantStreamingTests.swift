import Testing
import Foundation
@testable import RephrazeKit

@Suite("Token budget")
struct TokenBudgetTests {

    @Test("Short text still gets a workable floor")
    func floor() {
        #expect(OpenAIClient.tokenBudget(for: "hi") == 256)
    }

    @Test("Scales with input length")
    func scales() {
        // 4000 chars ~= 1000 tokens in, so 3000 out.
        let text = String(repeating: "a", count: 4000)
        #expect(OpenAIClient.tokenBudget(for: text) == 3000)
    }

    @Test("Capped so a runaway response cannot stream forever")
    func ceiling() {
        let text = String(repeating: "a", count: 100_000)
        #expect(OpenAIClient.tokenBudget(for: text) == 4096)
    }

    @Test("Empty text does not produce a zero budget")
    func empty() {
        #expect(OpenAIClient.tokenBudget(for: "") == 256)
    }
}

@Suite("Single-variant prompt")
struct SingleVariantPromptTests {

    @Test("Names only its own job, not the other three")
    func isolated() {
        let prompt = Prompt.singleVariantSystem(for: .concise)
        #expect(prompt.contains(RephraseVariant.concise.instruction))
        for other in RephraseVariant.allCases where other != .concise {
            #expect(!prompt.contains(other.instruction))
        }
    }

    @Test("Shorter than the combined prompt -- this is what keeps the cost close")
    func shorter() {
        for variant in RephraseVariant.allCases {
            #expect(Prompt.singleVariantSystem(for: variant).count
                    < Prompt.variantsSystem.count)
        }
    }

    @Test("Keeps the rules that protect the user's text")
    func rules() {
        let prompt = Prompt.singleVariantSystem(for: .polished)
        #expect(prompt.contains("ONLY the rewritten text"))
        #expect(prompt.contains("@mentions"))
    }
}

@MainActor
@Suite("Panel streaming slots")
struct PanelStreamingTests {

    private func model() -> ResultPanelModel {
        let m = ResultPanelModel()
        m.beginStreaming(original: "the original")
        return m
    }

    @Test("Every variant gets a slot up front, so rows never move")
    func slotsExistImmediately() {
        let m = model()
        #expect(m.slots.count == RephraseVariant.allCases.count)
        #expect(!m.isSettled)
    }

    @Test("Deltas accumulate into one variant only")
    func deltasAccumulate() {
        let m = model()
        m.append("Hello", to: .polished)
        m.append(" there", to: .polished)
        #expect(m.slots[.polished]?.text == "Hello there")
        #expect(m.slots[.concise]?.text == "")
    }

    @Test("A half-streamed variant cannot be applied")
    func partialNotChoosable() {
        let m = model()
        var chosen: String?
        m.onApply = { _, text in chosen = text }

        m.append("half a sen", to: .polished)
        m.choose(.polished)
        #expect(chosen == nil)

        m.complete(.polished)
        m.choose(.polished)
        #expect(chosen == "half a sen")
    }

    @Test("Digit N maps to the Nth variant regardless of arrival order")
    func digitsAreStable() {
        let m = model()
        var chosen: String?
        m.onApply = { label, _ in chosen = label }

        // Third variant lands first.
        m.append("formal text", to: .professional)
        m.complete(.professional)

        // Pressing 3 still picks it, not 1.
        m.chooseByDigit(3)
        #expect(chosen == RephraseVariant.professional.title)

        // And 1 does nothing, because polished has not arrived.
        chosen = nil
        m.chooseByDigit(1)
        #expect(chosen == nil)
    }

    @Test("Completing trims surrounding whitespace")
    func completeTrims() {
        let m = model()
        m.append("  spaced out \n", to: .friendly)
        m.complete(.friendly)
        #expect(m.slots[.friendly]?.text == "spaced out")
    }

    @Test("One failure leaves the others usable")
    func partialFailure() {
        let m = model()
        m.append("fine", to: .polished); m.complete(.polished)
        m.fail(.concise, message: "rate limited")
        m.append("also fine", to: .professional); m.complete(.professional)
        m.append("good", to: .friendly); m.complete(.friendly)

        #expect(m.isSettled)
        #expect(!m.isAllFailed)
        #expect(m.slots[.concise]?.isChoosable == false)
        #expect(m.slots[.polished]?.isChoosable == true)
    }

    @Test("All four failing is reported as a total failure")
    func totalFailure() {
        let m = model()
        for variant in RephraseVariant.allCases {
            m.fail(variant, message: "no network")
        }
        #expect(m.isSettled)
        #expect(m.isAllFailed)
    }

    @Test("A variant that finishes empty is not choosable")
    func emptyCompletion() {
        let m = model()
        m.complete(.polished)
        #expect(m.slots[.polished]?.isComplete == true)
        #expect(m.slots[.polished]?.isChoosable == false)
    }

    @Test("Original text survives for the history record")
    func originalKept() {
        let m = model()
        #expect(m.currentOriginal == "the original")
    }
}
