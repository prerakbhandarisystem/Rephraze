import AppKit
import SwiftUI
import Combine

/// A section of the settings window, and everything the sidebar needs to draw
/// it.
///
/// Title, icon and summary live here rather than at the call site, so adding a
/// section is one case with its properties filled in -- not an edit in three
/// separate places that can disagree with each other.
public enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case style
    case history
    case usage
    case support

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .style:   return "Writing style"
        case .history: return "History"
        case .usage:   return "Usage"
        case .support: return "Support"
        }
    }

    public var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .style:   return "signature"
        case .history: return "clock.arrow.circlepath"
        case .usage:   return "chart.bar"
        case .support: return "lifepreserver"
        }
    }

    /// One line under the title in the sidebar, so the window explains itself
    /// rather than making you click each section to find out what it is.
    public var summary: String {
        switch self {
        case .general: return "Key, model and speed"
        case .style:   return "Teach it how you write"
        case .history: return "What it has rewritten"
        case .usage:   return "Anonymous, off by default"
        case .support: return "Report a problem"
        }
    }
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

    // MARK: - Usage reporting

    @Published public var usageReportingEnabled: Bool = false
    @Published public var queuedUsageEvents: Int = 0

    // MARK: - Support

    @Published public var ticketKind: TicketKind = .bug
    @Published public var ticketSummary: String = ""
    @Published public var ticketDetail: String = ""
    @Published public var ticketIncludesDiagnostics: Bool = true
    @Published public var ticketStatus: TicketStatus = .idle
    /// Read when the section appears rather than on every view update, so the
    /// list on screen is exactly the list that will be sent.
    @Published public var diagnostics: Diagnostics = Diagnostics(fields: [])

    @Published public var records: [RephraseRecord] = []
    @Published public var searchTerm: String = ""
    @Published public var status: Status = .idle
    @Published public var selectedSection: SettingsSection = .general

    public enum Status: Equatable {
        case idle
        case saved
        case error(String)
    }

    public enum TicketStatus: Equatable {
        case idle
        /// Handed to the mail client. Whether it is actually sent is now the
        /// sender's decision, and the wording on screen says so.
        case handedOff
        /// No mail client took it, so the report went to the clipboard instead.
        case copied
    }

    private let history: HistoryStore
    private let telemetry: Telemetry

    /// Models worth defaulting to. Anything else can be typed in.
    public static let suggestedModels = [
        "gpt-4o-mini",
        "gpt-4.1-mini",
        "gpt-4o",
        "gpt-4.1",
    ]

    public init(history: HistoryStore, telemetry: Telemetry) {
        self.history = history
        self.telemetry = telemetry
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
        usageReportingEnabled = telemetry.isEnabled
        queuedUsageEvents = telemetry.queuedCount
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

    // MARK: - Usage reporting

    /// True when this build has somewhere to send reports at all. When it does
    /// not, the toggle is meaningless and the section says so rather than
    /// offering a switch that does nothing.
    public var usageEndpointConfigured: Bool { AppInfo.usageEndpoint != nil }

    public var usageEndpointDescription: String {
        AppInfo.usageEndpoint?.absoluteString ?? "not set in this build"
    }

    public func setUsageReporting(_ enabled: Bool) {
        telemetry.isEnabled = enabled
        usageReportingEnabled = enabled
        queuedUsageEvents = telemetry.queuedCount
        if enabled { telemetry.start() } else { telemetry.stop() }
    }

    /// Forget this install and start again as a new one.
    public func resetInstallID() {
        telemetry.resetInstallID()
        queuedUsageEvents = telemetry.queuedCount
    }

    public var installID: String { Telemetry.installID }

    /// The events this build is capable of sending, spelled out. Written by
    /// hand against `UsageEvent` so the screen is a claim someone has to keep
    /// true, not a reflection that quietly grows a new field.
    public static let usageEventDescriptions: [(String, String)] = [
        ("launched", "that the app started — nothing else"),
        ("rephrased", "accepted, dismissed or failed · whether your style was used · how long it took"),
        ("translated", "which of the ten languages"),
        ("failed", "network, service, cancelled or other"),
    ]

    // MARK: - Support

    /// Re-read the diagnostics. Called when the section appears, so revoking
    /// Accessibility access while the window sits open still shows up here.
    public func refreshDiagnostics() {
        diagnostics = Diagnostics.current(
            historyEnabled: history.isEnabled,
            historyCount: history.count
        )
    }

    public var ticket: SupportTicket {
        SupportTicket(
            kind: ticketKind,
            summary: ticketSummary,
            detail: ticketDetail,
            includesDiagnostics: ticketIncludesDiagnostics,
            diagnostics: diagnostics
        )
    }

    public var canSendTicket: Bool { ticket.isSendable }

    /// Open the report in the user's mail client.
    ///
    /// Nothing leaves the machine here -- the message is composed and left for
    /// the sender to read and send. If no client takes it, the report goes to
    /// the clipboard rather than vanishing along with what they just wrote.
    public func sendTicket() {
        guard canSendTicket else { return }
        let ticket = ticket

        if let url = ticket.mailtoURL(to: AppInfo.supportEmail),
           NSWorkspace.shared.open(url) {
            ticketStatus = .handedOff
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                ticket.plainText(to: AppInfo.supportEmail),
                forType: .string
            )
            ticketStatus = .copied
        }
    }

    /// Put the whole report on the clipboard, for pasting somewhere that isn't
    /// email.
    public func copyTicket() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            ticket.plainText(to: AppInfo.supportEmail),
            forType: .string
        )
        ticketStatus = .copied
    }

    /// Clear the form after a report has been handed off, so the next one
    /// starts empty rather than on top of the last.
    public func newTicket() {
        ticketSummary = ""
        ticketDetail = ""
        ticketStatus = .idle
    }

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
