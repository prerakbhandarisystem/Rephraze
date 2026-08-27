import SwiftUI
import Combine

public enum SettingsTab: Hashable {
    case general
    case history
}

/// Backing state for the settings window.
@MainActor
public final class SettingsModel: ObservableObject {

    @Published public var apiKeyInput: String = ""
    @Published public var hasStoredKey: Bool = false
    @Published public var model: String = Settings.model
    @Published public var historyEnabled: Bool = true
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
}
