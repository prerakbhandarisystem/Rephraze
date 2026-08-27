import SwiftUI
import Combine

public enum SettingsTab: Hashable {
    case general
    case style
    case history
}

/// Backing state for the settings window.
@MainActor
public final class SettingsModel: ObservableObject {

    @Published public var apiKeyInput: String = ""
    @Published public var hasStoredKey: Bool = false
    @Published public var model: String = Settings.model
    @Published public var historyEnabled: Bool = true
    @Published public var parallelVariants: Bool = Settings.useParallelVariants
    /// nil is "ask every time" rather than a missing value.
    @Published public var defaultLanguage: TargetLanguage? = Settings.defaultLanguage

    // MARK: - Writing style

    @Published public var styleAnswers: VoiceAnswers = [:]
    @Published public var styleText: String = ""
    @Published public var styleEnabled: Bool = true
    /// The order questions were answered in, so Back can walk it in reverse.
    @Published public var askedOrder: [String] = []
    /// A multi-answer question stays on screen until the user moves on, rather
    /// than jumping ahead the moment they tick one box.
    @Published public var stickyQuestionID: String?

    @Published public var records: [RephraseRecord] = []
    @Published public var searchTerm: String = ""
    @Published public var status: Status = .idle
    @Published public var selectedTab: SettingsTab = .general

    public enum Status: Equatable {
        case idle
        case saved
        case error(String)
    }

    private let history: HistoryStore

    /// Models worth defaulting to. Anything else can be typed in.
    public static let suggestedModels = [
        "gpt-4o-mini",
        "gpt-4.1-mini",
        "gpt-4o",
        "gpt-4.1",
    ]

    public init(history: HistoryStore) {
        self.history = history
        refresh()
    }

    public func refresh() {
        hasStoredKey = Keychain.hasAPIKey
        model = Settings.model
        historyEnabled = history.isEnabled
        parallelVariants = Settings.useParallelVariants
        defaultLanguage = Settings.defaultLanguage
        styleText = Settings.style
        styleEnabled = Settings.styleEnabled
        styleAnswers = Settings.styleAnswers
        // Rebuild the trail so Back still works after reopening the window.
        askedOrder = VoiceWizard.all.map(\.id).filter { !(styleAnswers[$0] ?? []).isEmpty }
        records = history.all
    }

    public var filteredRecords: [RephraseRecord] {
        history.search(searchTerm)
    }

    public func save() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            do {
                try Keychain.storeAPIKey(trimmed)
                apiKeyInput = ""
            } catch {
                status = .error(error.localizedDescription)
                return
            }
        }

        Settings.model = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Settings.defaultModel
            : model
        Settings.useParallelVariants = parallelVariants
        Settings.defaultLanguage = defaultLanguage

        status = .saved
        refresh()

        // Let the confirmation fade rather than linger.
        Task {
            try? await Task.sleep(for: .seconds(2))
            if status == .saved { status = .idle }
        }
    }

    public func removeKey() {
        try? Keychain.deleteAPIKey()
        apiKeyInput = ""
        refresh()
    }

    public func setHistoryEnabled(_ enabled: Bool) {
        history.isEnabled = enabled
        historyEnabled = enabled
    }

    public func clearHistory() {
        history.clear()
        refresh()
    }

    public var historyFileLocation: URL { history.fileLocation }

    // MARK: - Wizard

    /// The question on screen, or nil when the wizard has finished.
    ///
    /// A multi-answer question is held in place by `stickyQuestionID` so that
    /// ticking the first box does not skip to the next question.
    public var currentQuestion: VoiceQuestion? {
        if let stickyQuestionID,
           let held = VoiceWizard.all.first(where: { $0.id == stickyQuestionID }) {
            return held
        }
        return VoiceWizard.next(given: styleAnswers)
    }

    public var wizardProgress: (asked: Int, total: Int) {
        VoiceWizard.progress(given: styleAnswers)
    }

    public var wizardIsComplete: Bool {
        stickyQuestionID == nil && VoiceWizard.isComplete(styleAnswers)
    }

    /// True once there is a style to use, however it was written.
    public var hasStyle: Bool {
        !styleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Anything at all to reset -- answers given, or text written by hand.
    public var canStartOver: Bool {
        !styleAnswers.isEmpty || hasStyle
    }

    public func selection(for questionID: String) -> [String] {
        styleAnswers[questionID] ?? []
    }

    public func isSelected(_ questionID: String, _ optionID: String) -> Bool {
        selection(for: questionID).contains(optionID)
    }

    /// Pick an option. Single-answer questions advance; multi-answer ones
    /// toggle and wait for Continue.
    public func select(_ question: VoiceQuestion, _ optionID: String) {
        if question.allowsMultiple {
            var current = selection(for: question.id)
            if let index = current.firstIndex(of: optionID) {
                current.remove(at: index)
            } else {
                current.append(optionID)
            }
            styleAnswers[question.id] = current
            stickyQuestionID = question.id
        } else {
            styleAnswers[question.id] = [optionID]
            stickyQuestionID = nil
        }
        commitAnswers(recording: question.id)
    }

    /// Leave a multi-answer question and move to the next one.
    public func advance() {
        guard let stickyQuestionID else { return }
        self.stickyQuestionID = nil
        commitAnswers(recording: stickyQuestionID)
    }

    /// True when the Continue button should be offered and enabled.
    public var canAdvance: Bool {
        guard let stickyQuestionID else { return false }
        return !selection(for: stickyQuestionID).isEmpty
    }

    private func commitAnswers(recording questionID: String) {
        askedOrder.removeAll { $0 == questionID }
        if !selection(for: questionID).isEmpty {
            askedOrder.append(questionID)
        }

        // Later answers can make an earlier one irrelevant -- drop anything the
        // new state no longer asks, so the description never contains a phrase
        // from a question that does not apply.
        styleAnswers = VoiceWizard.pruned(styleAnswers)
        let live = Set(styleAnswers.keys)
        askedOrder.removeAll { !live.contains($0) }

        if VoiceWizard.isComplete(styleAnswers) && stickyQuestionID == nil {
            styleText = VoiceWizard.describe(styleAnswers)
        }

        // Persist every answer as it is given. Someone who quits halfway
        // through should come back to where they were, not to question one.
        Settings.styleAnswers = styleAnswers
    }

    public func goBack() {
        if stickyQuestionID != nil {
            stickyQuestionID = nil
            return
        }
        guard let last = askedOrder.last else { return }
        askedOrder.removeLast()
        styleAnswers.removeValue(forKey: last)
        Settings.styleAnswers = styleAnswers
    }

    public var canGoBack: Bool { stickyQuestionID != nil || !askedOrder.isEmpty }

    /// Throw everything away and ask from question one.
    public func startOver() {
        styleAnswers = [:]
        askedOrder = []
        stickyQuestionID = nil
        styleText = ""
        Settings.styleAnswers = [:]
        Settings.style = ""
    }

    /// Rebuild the description from the answers, discarding hand edits.
    public func regenerateStyleText() {
        styleText = VoiceWizard.describe(styleAnswers)
    }

    public func saveStyle() {
        Settings.style = styleText.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.styleEnabled = styleEnabled
        status = .saved

        Task {
            try? await Task.sleep(for: .seconds(2))
            if status == .saved { status = .idle }
        }
    }
}
