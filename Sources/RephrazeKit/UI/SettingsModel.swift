import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// A section of the settings window, and everything the sidebar needs to draw
/// it.
///
/// Title, icon and summary live here rather than at the call site, so adding a
/// section is one case with its properties filled in -- not an edit in three
/// separate places that can disagree with each other.
public enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case system
    case translation
    case style
    case history
    case account
    case team
    case billing
    case usage
    case help

    public var id: String { rawValue }

    /// The sidebar's two headed groups, in the order they appear.
    ///
    /// Two groups rather than one long list. The first is the app -- how it is
    /// triggered, how it behaves, how it writes. The second is you -- your key,
    /// the people you share a voice with, what it costs, what leaves the Mac.
    /// Nine rows in one column is a list you scan; nine rows under two honest
    /// headings is a list you navigate.
    public static let groups: [(title: String, sections: [SettingsSection])] = [
        ("Settings", [.general, .system, .translation, .style, .history]),
        ("Account", [.account, .team, .billing, .usage]),
    ]

    /// The one that lives in the corner instead of in the list.
    ///
    /// Nobody reads a list to find help -- they look in the corner, because
    /// every app has taught them to.
    public static let utility: [SettingsSection] = [.help]

    public var title: String {
        switch self {
        case .general:     return "General"
        case .system:      return "System"
        case .translation: return "Translation"
        case .style:       return "Writing style"
        case .history:     return "History"
        case .account:     return "Account"
        case .team:        return "Team"
        case .billing:     return "Plans and Billing"
        // Named for what it governs rather than for what it counts. "Usage"
        // beside "Plans and Billing" reads as the meter, and this is the
        // opposite of a meter -- it is the page that says nothing is collected.
        case .usage:       return "Data and Privacy"
        case .help:        return "Help"
        }
    }

    public var symbol: String {
        switch self {
        case .general:     return "gearshape"
        case .system:      return "laptopcomputer"
        case .translation: return "globe"
        case .style:       return "signature"
        case .history:     return "clock.arrow.circlepath"
        case .account:     return "person.crop.circle"
        case .team:        return "person.2"
        case .billing:     return "creditcard"
        case .usage:       return "hand.raised"
        case .help:        return "questionmark.circle"
        }
    }

    /// The chip colour behind the icon.
    ///
    /// One hue each, in a fixed order that never shifts -- the colour is how a
    /// section is recognised before the label is read, so a section whose
    /// colour moved would be a section you had to re-learn.
    ///
    /// Every one is dark enough to carry a white glyph at this size (all clear
    /// 4:1 against white). That rules out the bright yellows and mints that
    /// look best in a palette and worst under a 12pt symbol.
    public var tint: Color {
        switch self {
        case .general:     return Color(red: 0.165, green: 0.471, blue: 0.839)  // blue
        case .system:      return Color(red: 0.298, green: 0.337, blue: 0.396)  // slate
        case .translation: return Color(red: 0.043, green: 0.463, blue: 0.502)  // teal
        case .style:       return Color(red: 0.290, green: 0.227, blue: 0.655)  // violet
        case .history:     return Color(red: 0.090, green: 0.569, blue: 0.416)  // green
        case .account:     return Color(red: 0.600, green: 0.161, blue: 0.451)  // plum
        case .team:        return Color(red: 0.478, green: 0.325, blue: 0.204)  // brown
        case .billing:     return Color(red: 0.647, green: 0.427, blue: 0.063)  // amber
        case .usage:       return Color(red: 0.851, green: 0.329, blue: 0.122)  // orange
        case .help:        return Color(red: 0.812, green: 0.231, blue: 0.227)  // red
        }
    }

    /// One line under the title in the sidebar, so the window explains itself
    /// rather than making you click each section to find out what it is.
    public var summary: String {
        switch self {
        case .general:     return "The shortcut, the model, the speed"
        case .system:      return "Login, Dock, sound and alerts"
        case .translation: return "Coming soon"
        case .style:       return "Teach it how you write"
        case .history:     return "What it has rewritten"
        case .account:     return "Your key and who it bills"
        case .team:        return "Share how you write"
        case .billing:     return "What you get, what it costs"
        case .usage:       return "Anonymous, off by default"
        case .help:        return "Report a problem"
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

    // MARK: - The shortcut

    @Published public var triggerKey: TriggerKey = Settings.triggerKey
    @Published public var doubleTapWindow: TimeInterval = Settings.doubleTapWindow

    // MARK: - System

    /// Read back from macOS rather than from a preference, because macOS is
    /// where the truth is -- see `LoginItem`.
    @Published public var launchAtLogin: Bool = false
    @Published public var showsInDock: Bool = Settings.showsInDock
    @Published public var panelFollowsFullScreen: Bool = Settings.panelFollowsFullScreen
    @Published public var soundOnReady: Bool = Settings.soundOnReady
    @Published public var soundOnFailure: Bool = Settings.soundOnFailure
    @Published public var notifyOnFailure: Bool = Settings.notifyOnFailure
    @Published public var notifyWhenLow: Bool = Settings.notifyWhenLow
    /// Set when macOS turns down a request for notification access, so the
    /// switch can explain why it went back off instead of just going back off.
    @Published public var notificationsRefused: Bool = false

    // MARK: - Team

    /// What an exported profile will be called. Prefilled with something
    /// plausible so exporting is one click for anyone who does not care.
    @Published public var profileName: String = "Our writing style"
    @Published public var profileStatus: ProfileStatus = .idle

    public enum ProfileStatus: Equatable {
        case idle
        /// Written to a file the user chose. The name is echoed back because
        /// "Exported" alone leaves them hunting for where it went.
        case exported(String)
        case imported(String)
        case failed(String)
    }

    /// Told when the trigger or its timing changes, so the running event tap
    /// can be rebuilt. Set by whoever owns the tap; a no-op in tests.
    public var onHotkeyChanged: () -> Void = {}

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
    /// Filled in from the last report that was sent, so a second one does not
    /// mean typing the same address again.
    @Published public var ticketReplyTo: String = Settings.replyAddress
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
        /// On its way. The button is held down until the server answers,
        /// because the answer is the only thing worth showing.
        case sending
        /// In the inbox. Not "submitted", not "queued" -- it arrived.
        case sent
        /// This build has no endpoint, so the report was handed to the mail
        /// client instead. Whether it is actually sent is now the sender's
        /// decision, and the wording on screen says so.
        case handedOff
        /// No mail client took it, so the report went to the clipboard instead.
        case copied
        /// It did not go, and this is why. What was written is on the clipboard
        /// by the time this is shown.
        case failed(String)
    }

    private let history: HistoryStore
    private let telemetry: Telemetry
    private let tickets: TicketSender

    /// Models worth defaulting to. Anything else can be typed in.
    public static let suggestedModels = [
        "gpt-4o-mini",
        "gpt-4.1-mini",
        "gpt-4o",
        "gpt-4.1",
    ]

    public init(
        history: HistoryStore,
        telemetry: Telemetry,
        tickets: TicketSender = TicketSender()
    ) {
        self.history = history
        self.telemetry = telemetry
        self.tickets = tickets
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
        triggerKey = Settings.triggerKey
        doubleTapWindow = Settings.doubleTapWindow
        launchAtLogin = LoginItem.isEnabled
        showsInDock = Settings.showsInDock
        panelFollowsFullScreen = Settings.panelFollowsFullScreen
        soundOnReady = Settings.soundOnReady
        soundOnFailure = Settings.soundOnFailure
        notifyOnFailure = Settings.notifyOnFailure
        notifyWhenLow = Settings.notifyWhenLow
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


    // MARK: - The shortcut

    /// Change the key you tap twice, and restart the listener on the spot.
    ///
    /// Applied immediately rather than on Done. A shortcut is the one setting
    /// here you verify by trying it, and a picker that needs a second button
    /// pressed before the key works makes the first attempt fail for no reason.
    public func setTriggerKey(_ key: TriggerKey) {
        guard key != triggerKey else { return }
        triggerKey = key
        Settings.triggerKey = key
        onHotkeyChanged()
    }

    public func setDoubleTapWindow(_ window: TimeInterval) {
        guard window != doubleTapWindow else { return }
        doubleTapWindow = window
        Settings.doubleTapWindow = window
        onHotkeyChanged()
    }

    /// The speeds offered, tightest gap first.
    ///
    /// Three named choices rather than a slider over milliseconds. Nobody knows
    /// what 0.4 seconds feels like until they have missed it twice, and the
    /// three that matter are "I keep firing it by accident", "fine", and "it
    /// never catches my second tap".
    public static let doubleTapSpeeds: [(name: String, seconds: TimeInterval, note: String)] = [
        ("Quick", 0.28, "Both taps have to be deliberate. Fewest accidents."),
        ("Standard", DoubleTapDetector.defaultWindow, "The same gap macOS uses for a double-click."),
        ("Relaxed", 0.60, "More time for the second tap, at the cost of the odd accidental one."),
    ]

    /// How the current shortcut reads in a sentence, e.g. "⌥⌥".
    public var triggerDescription: String {
        String(repeating: triggerKey.displayName, count: 2)
    }

    // MARK: - System

    /// Ask macOS to launch the app at login, then show what macOS decided.
    ///
    /// The switch is set from the result, not from the request. Registering can
    /// fail -- an unsigned build, an app still sitting in Downloads -- and a
    /// switch that stays on after a failed registration is a switch that lies.
    public func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LoginItem.setEnabled(enabled)
    }

    /// False when there is no bundle for macOS to register.
    public var canLaunchAtLogin: Bool { LoginItem.isAvailable }

    /// Show or hide the Dock icon.
    ///
    /// Turning it on takes effect now; turning it off waits for this window to
    /// close. A window belonging to an app with no Dock icon cannot be reached
    /// with ⌘-Tab, so taking the icon away while you are still looking at the
    /// window would strand it behind whatever you click next.
    public func setShowsInDock(_ enabled: Bool) {
        showsInDock = enabled
        Settings.showsInDock = enabled
        if enabled { DockPresence.raiseForWindow() }
    }

    public func setPanelFollowsFullScreen(_ enabled: Bool) {
        panelFollowsFullScreen = enabled
        Settings.panelFollowsFullScreen = enabled
    }

    public func setSoundOnReady(_ enabled: Bool) {
        soundOnReady = enabled
        Settings.soundOnReady = enabled
        // Play it as it is switched on. A sound setting you cannot hear until
        // the next time the thing happens is a setting you have to guess at.
        if enabled { Feedback.rewriteReady() }
    }

    public func setSoundOnFailure(_ enabled: Bool) {
        soundOnFailure = enabled
        Settings.soundOnFailure = enabled
        if enabled { Feedback.rewriteFailed() }
    }

    public func setNotifyOnFailure(_ enabled: Bool) {
        setNotification(
            enabled,
            store: { Settings.notifyOnFailure = $0 },
            show: { [weak self] in self?.notifyOnFailure = $0 }
        )
    }

    public func setNotifyWhenLow(_ enabled: Bool) {
        setNotification(
            enabled,
            store: { Settings.notifyWhenLow = $0 },
            show: { [weak self] in self?.notifyWhenLow = $0 }
        )
    }

    /// False in a build with no bundle, where macOS will not deliver at all.
    public var notificationsAvailable: Bool { Feedback.notificationsAvailable }

    /// Turn a notification switch on only if macOS agrees to deliver them.
    ///
    /// Permission is asked for here, at the moment someone opts in, rather than
    /// at launch. An app that asks before it has anything to notify you about
    /// gets refused, and that refusal sticks until somebody goes hunting
    /// through System Settings to undo it.
    private func setNotification(
        _ enabled: Bool,
        store: @escaping (Bool) -> Void,
        show: @escaping (Bool) -> Void
    ) {
        guard enabled else {
            show(false)
            store(false)
            notificationsRefused = false
            return
        }

        // Shown on immediately so the switch follows the finger, then corrected
        // from what macOS actually says.
        show(true)
        Task {
            let granted = await Feedback.requestNotificationAccess()
            notificationsRefused = !granted
            show(granted)
            store(granted)
        }
    }

    // MARK: - Team

    /// Write the writing style now in use out to a file the user picks.
    public func exportStyleProfile() {
        guard hasStyle else {
            profileStatus = .failed("There is no writing style to share yet.")
            return
        }

        let profile = StyleProfile.current(named: profileName)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = profile.suggestedFilename
        panel.canCreateDirectories = true
        panel.message = "Anyone with this file can write in your voice. "
            + "It carries no key and nothing you have rephrased."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try profile.encoded().write(to: url, options: .atomic)
            profileStatus = .exported(url.lastPathComponent)
        } catch {
            profileStatus = .failed(error.localizedDescription)
        }
    }

    /// Read a profile from disk and adopt it as this Mac's writing style.
    public func importStyleProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // JSON stays in the list beside our own type. A profile is plain JSON
        // underneath, and somebody will rename one on the way through a chat
        // app or an email attachment.
        panel.allowedContentTypes = [
            UTType(filenameExtension: StyleProfile.fileExtension),
            .json,
        ].compactMap { $0 }
        panel.message = "Choose a writing style someone exported from Rephraze."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let profile = try StyleProfile.decoded(from: Data(contentsOf: url))
            profile.apply()
            profileName = profile.name
            profileStatus = .imported(profile.name)
            refresh()
        } catch {
            profileStatus = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    // MARK: - Plan

    /// The allowance, read fresh each time it is asked for.
    ///
    /// A value type over UserDefaults, and the count only moves while the panel
    /// is in use -- which is to say while this window is not the one being
    /// looked at. Nothing here needs to observe it.
    public var quota: UsageQuota { UsageQuota() }

    /// Where OpenAI shows what the key has actually cost.
    ///
    /// The bill is theirs, not ours: the key in this app is billed by OpenAI
    /// directly, and no charge passes through Rephraze at any point. That makes
    /// the honest thing to put here a link, not a number we would be guessing at.
    public static let openAIBillingURL = URL(string: "https://platform.openai.com/usage")!

    public func openOpenAIBilling() {
        NSWorkspace.shared.open(Self.openAIBillingURL)
    }

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
            replyTo: ticketReplyTo,
            includesDiagnostics: ticketIncludesDiagnostics,
            diagnostics: diagnostics
        )
    }

    public var canSendTicket: Bool { ticket.isSendable && ticketStatus != .sending }

    /// Something was typed in the reply field that could not receive a reply.
    /// Said on the screen while it can still be fixed, rather than discovered
    /// when the answer bounces a day later.
    public var replyAddressLooksWrong: Bool {
        let typed = ticket.replyAddress
        return !typed.isEmpty && !SupportTicket.looksLikeAnAddress(typed)
    }

    /// True when this build sends reports itself. When it is false the button
    /// still works, by way of the mail client -- but it says something else,
    /// because it does something else.
    public var sendsTicketsDirectly: Bool { tickets.canSend }

    /// Send the report.
    ///
    /// It goes now, in one press: no mail client to open, no second send
    /// button somewhere else, no draft left sitting in a folder. The screen
    /// waits for the server to say it went, because anything shown before that
    /// would be a guess.
    ///
    /// If it cannot go -- no endpoint in this build, or the server is
    /// unreachable -- the report is never simply lost. It goes to the mail
    /// client, or failing that to the clipboard, along with a line saying so.
    public func sendTicket() {
        guard canSendTicket else { return }
        let ticket = ticket

        guard sendsTicketsDirectly else { return handToMailClient(ticket) }

        Settings.replyAddress = ticket.replyAddress
        ticketStatus = .sending

        Task {
            do {
                try await tickets.send(ticket)
                ticketStatus = .sent
            } catch {
                // Whatever went wrong on the way, what they wrote must survive
                // it -- so it is on the clipboard before they are told.
                copyToPasteboard(ticket)
                ticketStatus = .failed(
                    (error as? LocalizedError)?.errorDescription
                        ?? "That report did not go."
                )
            }
        }
    }

    /// Compose the report in the user's own mail client. The fallback for a
    /// build with nowhere to post to; if no client takes it, the report goes to
    /// the clipboard rather than vanishing along with what they just wrote.
    private func handToMailClient(_ ticket: SupportTicket) {
        if let url = ticket.mailtoURL(to: AppInfo.supportEmail),
           NSWorkspace.shared.open(url) {
            ticketStatus = .handedOff
        } else {
            copyToPasteboard(ticket)
            ticketStatus = .copied
        }
    }

    /// Put the whole report on the clipboard, for pasting somewhere that isn't
    /// email.
    public func copyTicket() {
        copyToPasteboard(ticket)
        ticketStatus = .copied
    }

    private func copyToPasteboard(_ ticket: SupportTicket) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            ticket.plainText(to: AppInfo.supportEmail),
            forType: .string
        )
    }

    /// Clear the form after a report has gone, so the next one starts empty
    /// rather than on top of the last. The reply address stays -- it is the one
    /// part that is the same every time.
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
