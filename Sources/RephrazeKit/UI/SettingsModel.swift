import SwiftUI
import Combine

public enum SettingsTab: Hashable {
    case general
    case voice
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

    // MARK: - Your voice

    @Published public var voiceAnswers: [String: String] = [:]
    @Published public var voiceText: String = ""
    @Published public var voiceEnabled: Bool = true
    /// The order questions were asked in, so Back can walk it in reverse.
    @Published public var askedOrder: [String] = []
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
        voiceText = Settings.voice
        voiceEnabled = Settings.voiceEnabled
        voiceAnswers = Settings.voiceAnswers
        // Rebuild the trail so Back still works after reopening the window.
        askedOrder = VoiceWizard.all.map(\.id).filter { voiceAnswers[$0] != nil }
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
    public var currentQuestion: VoiceQuestion? {
        VoiceWizard.next(given: voiceAnswers)
    }

    public var wizardProgress: (asked: Int, total: Int) {
        VoiceWizard.progress(given: voiceAnswers)
    }

    public var wizardIsComplete: Bool {
        VoiceWizard.isComplete(voiceAnswers)
    }

    /// True once there is a voice to use, however it was written.
    public var hasVoice: Bool {
        !voiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func answer(_ questionID: String, with optionID: String) {
        voiceAnswers[questionID] = optionID
        askedOrder.removeAll { $0 == questionID }
        askedOrder.append(questionID)

        // Later answers can make an earlier one irrelevant -- drop anything the
        // new state no longer asks, so the description never contains a phrase
        // from a question that does not apply.
        let allowed = Set(VoiceWizard.applicable(given: voiceAnswers).map(\.id))
        for key in voiceAnswers.keys where !allowed.contains(key) {
            voiceAnswers.removeValue(forKey: key)
            askedOrder.removeAll { $0 == key }
        }

        if VoiceWizard.isComplete(voiceAnswers) {
            voiceText = VoiceWizard.describe(voiceAnswers)
        }

        // Persist every answer as it is given. Someone who quits halfway
        // through should come back to where they were, not to question one.
        Settings.voiceAnswers = voiceAnswers
    }

    public func goBack() {
        guard let last = askedOrder.last else { return }
        askedOrder.removeLast()
        voiceAnswers.removeValue(forKey: last)
        Settings.voiceAnswers = voiceAnswers
    }

    public var canGoBack: Bool { !askedOrder.isEmpty }

    public func restartWizard() {
        voiceAnswers = [:]
        askedOrder = []
        Settings.voiceAnswers = [:]
    }

    /// Rebuild the description from the answers, discarding hand edits.
    public func regenerateVoiceText() {
        voiceText = VoiceWizard.describe(voiceAnswers)
    }

    public func saveVoice() {
        Settings.voice = voiceText.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.voiceEnabled = voiceEnabled
        status = .saved

        Task {
            try? await Task.sleep(for: .seconds(2))
            if status == .saved { status = .idle }
        }
    }

    public func clearVoice() {
        voiceText = ""
        voiceAnswers = [:]
        askedOrder = []
        Settings.voice = ""
        Settings.voiceAnswers = [:]
    }
}
