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
        case failed(String)
    }

    @Published public var state: State = .loading
    @Published public var appName: String = ""

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

    public var personalIsChoosable: Bool {
        personalComplete && !personalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Called when the user picks one.
    public var onChoose: ((RephraseVariant, String) -> Void)?
    public var onCancel: (() -> Void)?
    /// Called when the user takes the single personalised rewrite.
    public var onChoosePersonal: ((String) -> Void)?

    public init() {}

    // MARK: - Streaming path

    public func beginStreaming(original: String) {
        self.original = original
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
        slot.text = slot.text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - Personal voice path

    public func beginPersonal(original: String) {
        self.original = original
        personalText = ""
        personalComplete = false
        state = .personal
    }

    public func appendPersonal(_ delta: String) {
        personalText += delta
    }

    public func completePersonal() {
        personalText = personalText.trimmingCharacters(in: .whitespacesAndNewlines)
        personalComplete = true
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

    /// Pick by number key, 1-4.
    public func chooseByDigit(_ digit: Int) {
        switch state {
        case .personal:
            // Only one thing on screen, so only "1" means anything.
            guard digit == 1 else { return }
            choosePersonal()
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
