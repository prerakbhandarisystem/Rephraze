import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusMenu = StatusMenu()
    private var eventTap: EventTap?
    // Option, not Command: macOS binds "press either Command key twice" to
    // Siri, so ⌘⌘ opens Siri instead of us. ⌥ has no system double-tap binding.
    // One-line change if this ever collides with something.
    private let trigger: TriggerKey = .option
    private var permissionPoll: Timer?
    private let onboarding = OnboardingWindow()
    private let settingsWindow = SettingsWindow()
    private let history = HistoryStore()
    private let openAI = OpenAIClient()
    private var activeRephrase: Task<Void, Never>?
    private let panel = ResultPanel()

    /// The field the current picker belongs to, captured before the round trip
    /// so the target can never drift.
    private var pendingField: FocusedField?
    private var pendingWasSelection = false
    private var pendingOriginal = ""
    private var pendingRecordID: UUID?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Must exist before any window opens, or ⌘V will not work in text fields.
        MainMenu.install()
        statusMenu.install()
        statusMenu.isHotkeyRunning = { [weak self] in self?.eventTap?.isRunning ?? false }
        statusMenu.onRequestPermission = { [weak self] in self?.requestPermission() }
        statusMenu.triggerName = { [weak self] in
            self?.trigger.displayName ?? TriggerKey.command.displayName
        }

        statusMenu.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        statusMenu.onOpenStyle = { [weak self] in self?.settingsWindow.show(tab: .style) }
        settingsWindow.history = history
        onboarding.onGranted = { [weak self] in self?.startListening() }

        panel.model.onChoose = { [weak self] variant, text in
            self?.apply(label: variant.title, text: text)
        }
        panel.model.onChoosePersonal = { [weak self] text in
            self?.apply(label: "your style", text: text)
        }
        panel.model.onChooseLanguage = { [weak self] language in
            self?.translate(into: language)
        }
        panel.model.onChooseTranslation = { [weak self] text in
            guard let self else { return }
            self.apply(label: self.panel.model.activeLanguage?.title ?? "translation", text: text)
        }
        panel.model.onStateChange = { [weak self] in self?.syncPanelDigits() }
        panel.model.onRequestEditing = { [weak self] in self?.beginEditing() }
        panel.model.onRefine = { [weak self] instruction in self?.refine(with: instruction) }

        // No window at all is the right look once this works -- but on a first
        // launch with no permission it reads as "nothing happened". Say so.
        Log.app.notice("Launched. Accessibility trusted = \(Permissions.isTrusted)")
        if Permissions.isTrusted {
            startListening()

            // Permission is granted but there is no key, so a double-tap would
            // fail. Say so up front instead of at the worst moment.
            if !Keychain.hasAPIKey {
                Log.app.notice("No API key stored -- opening settings")
                settingsWindow.show()
            }
        } else {
            // Fire the native macOS prompt first. It is the most reliable way to
            // get an app into the Accessibility list -- macOS adds the entry
            // itself, rather than relying on the user finding it with the + button.
            Permissions.requestAccess()
            onboarding.show()
            waitForPermission()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        permissionPoll?.invalidate()
        eventTap?.stop()
    }

    /// Menu bar apps stay running with no windows open.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the app in Finder or the Dock while it is already running.
    ///
    /// A menu-bar-only app does nothing here by default, which reads exactly
    /// like a broken app -- you double-click it and the screen does not change.
    /// Opening Settings gives the click somewhere to land.
    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        if Permissions.isTrusted {
            settingsWindow.show()
        } else {
            onboarding.show()
        }
        return true
    }

    // MARK: - Hotkey

    private func startListening() {
        // Both the permission poll and the onboarding window can report success,
        // so this can be called twice. Starting a second tap would leave the
        // first one running.
        guard eventTap == nil else { return }

        guard Permissions.isTrusted else {
            Log.app.notice("No Accessibility access yet -- waiting for it")
            waitForPermission()
            return
        }

        let tap = EventTap(trigger: trigger) { [weak self] signal in
            self?.handle(signal)
        }

        if tap.start() {
            eventTap = tap
            Log.app.notice("Listening for double-tap \(self.trigger.rawValue, privacy: .public)")
        } else {
            // Trusted but the tap still failed. Retry rather than dying silently.
            Log.app.error("Event tap failed to start despite having access")
            waitForPermission()
        }
    }

    private func handle(_ signal: EventTap.Signal) {
        switch signal {
        case .doubleTap:
            Log.hotkey.notice("TRIGGER FIRED")
            runCapture()

        case .soloTap:
            // People tap a modifier alone by accident constantly. Ignored.
            break

        case .escape:
            // esc unwinds one step at a time rather than always closing: while
            // typing a follow-up it means "stop typing", and over the language
            // list it means "back to the rewrites". Only at the top does it
            // dismiss. Opening the list by mistake must not cost four rewrites
            // that already arrived.
            if panel.model.isEditing {
                panel.endEditing(restoringFocusTo: pendingField?.pid)
                eventTap?.wantsPanelKeys = true
            } else if panel.model.closeLanguages() {
                break
            } else {
                dismissPanel()
            }

        case .refine:
            // The language list has no follow-up box, so there is nothing for
            // focus to land in -- and taking it would pull the caret out of the
            // user's text field for no reason.
            guard !panel.model.isChoosingLanguage else { break }
            beginEditing()

        case .translate:
            guard panel.isVisible, !panel.model.isEditing else { break }
            // A saved default makes this one keystroke instead of two. Pressing
            // it again, while that translation is on screen, opens the full
            // list -- so the default is a shortcut past the menu rather than a
            // lock-in to one language.
            if let language = Settings.defaultLanguage, panel.model.activeLanguage == nil {
                translate(into: language)
            } else {
                panel.model.showLanguages()
            }

        case let .digit(index):
            panel.model.chooseByDigit(index)

        case .dismiss:
            // The user carried on typing. Get out of the way -- unless they are
            // typing into our own box, where the keys are meant for us.
            guard !panel.model.isEditing else { break }
            dismissPanel()
        }
    }

    // MARK: - Capture

    /// Read whatever text box has focus, and report what happened.
    ///
    /// Note what is logged: the role, the app, and a character count -- never
    /// the text itself. Writing captured text to the system log would persist
    /// your typing to disk, which is exactly what this app must not do. The
    /// text goes only to the menu, where you are the sole reader.
    private func runCapture() {
        let result = TextCapture.capture()

        switch result {
        case let .captured(capture):
            let kind = capture.wasSelection ? "selection" : "whole field"
            Log.capture.notice("""
                Captured \(capture.text.count) chars (\(kind, privacy: .public))                 from \(capture.field.appName, privacy: .public)                 role=\(capture.field.role, privacy: .public)
                """)
            statusMenu.flashTap(success: true)
            statusMenu.setLastCapture(
                summary: "Rephrasing \(capture.text.count) chars from \(capture.field.appName)…",
                preview: Self.preview(of: capture.text)
            )
            rephrase(capture)

        case let .notATextField(role, app):
            Log.capture.notice("Not a text field: role=\(role, privacy: .public) in \(app, privacy: .public)")
            statusMenu.flashTap(success: false)
            statusMenu.setLastCapture(summary: "Not a text box — \(role) in \(app)", preview: nil)

        case let .secureField(app):
            Log.capture.notice("Refused: password field in \(app, privacy: .public)")
            statusMenu.flashTap(success: false)
            statusMenu.setLastCapture(summary: "Refused — password field in \(app)", preview: nil)

        case let .blockedApp(app):
            Log.capture.notice("Refused: blocked app \(app, privacy: .public)")
            statusMenu.flashTap(success: false)
            statusMenu.setLastCapture(summary: "Refused — \(app) is on the blocklist", preview: nil)

        case let .empty(app):
            Log.capture.notice("Empty text box in \(app, privacy: .public)")
            statusMenu.flashTap(success: false)
            statusMenu.setLastCapture(summary: "Text box is empty — \(app)", preview: nil)

        case .noFocus:
            Log.capture.notice("Nothing focused")
            statusMenu.flashTap(success: false)
            statusMenu.setLastCapture(summary: "Nothing has keyboard focus", preview: nil)
        }
    }

    // MARK: - Rephrase

    /// Ask for four rewrites, show them, and wait for a choice.
    private func rephrase(_ capture: CapturedText) {
        guard let apiKey = Keychain.readAPIKey() else {
            Log.rewrite.notice("No API key stored")
            statusMenu.setLastCapture(summary: "No API key — open Settings", preview: nil)
            settingsWindow.show(tab: .general)
            return
        }

        // Remember the target now. Re-deriving focus after the network round
        // trip could land the text somewhere else entirely.
        pendingField = capture.field
        pendingWasSelection = capture.wasSelection
        pendingOriginal = capture.text
        pendingRecordID = nil

        // Only one in flight. A second trigger replaces the first rather than
        // racing it, so two rewrites can never land in the same box.
        activeRephrase?.cancel()

        panel.model.state = .loading
        panel.model.appName = capture.field.appName
        panel.show(near: capture.field)
        eventTap?.wantsPanelKeys = true

        let original = capture.text
        let appName = capture.field.appName
        let model = Settings.model
        let started = Date()

        // A described voice replaces the four-way choice entirely: they have
        // already said how they want to sound, so asking again is a step
        // backwards.
        if Settings.usesWritingStyle {
            let style = Settings.style
            panel.model.beginPersonal(original: original)

            activeRephrase = Task { [weak self] in
                guard let self else { return }
                var sawText = false
                do {
                    for try await delta in openAI.rephrasePersonal(
                        text: original, style: style, model: model, apiKey: apiKey
                    ) {
                        if Task.isCancelled { return }
                        if !sawText {
                            sawText = true
                            Log.rewrite.notice(
                                "First text after \(Int(Date().timeIntervalSince(started) * 1000))ms"
                            )
                        }
                        await self.panel.model.appendPersonal(delta)
                    }

                    guard !Task.isCancelled else { return }
                    await self.finishPersonal(
                        original: original, appName: appName, started: started
                    )
                } catch is CancellationError {
                    return
                } catch {
                    await self.showFailure(error.localizedDescription)
                }
            }
            return
        }

        if Settings.useParallelVariants {
            panel.model.beginStreaming(original: original)

            activeRephrase = Task { [weak self] in
                guard let self else { return }
                var firstAt: TimeInterval?

                for await event in openAI.rephraseVariantsStreaming(
                    text: original, model: model, apiKey: apiKey
                ) {
                    if Task.isCancelled { return }

                    switch event {
                    case let .delta(variant, chunk):
                        // Time to first visible word -- the number that decides
                        // whether this feels fast.
                        if firstAt == nil {
                            let ms = Int(Date().timeIntervalSince(started) * 1000)
                            firstAt = Double(ms)
                            Log.rewrite.notice("First text after \(ms)ms")
                        }
                        await self.panel.model.append(chunk, to: variant)

                    case let .finished(variant):
                        await self.panel.model.complete(variant)

                    case let .failed(variant, message):
                        Log.rewrite.error("""
                            \(variant.rawValue, privacy: .public) failed: \
                            \(message, privacy: .public)
                            """)
                        await self.panel.model.fail(variant, message: message)
                    }
                }

                guard !Task.isCancelled else { return }
                await self.finishStreaming(
                    original: original, appName: appName, started: started
                )
            }
            return
        }

        activeRephrase = Task { [weak self] in
            do {
                let set = try await self?.openAI.rephraseVariants(
                    text: original, model: model, apiKey: apiKey
                )
                guard let set, !Task.isCancelled else { return }

                Log.rewrite.notice("""
                    Got \(set.available.count) variants for \(original.count) chars \
                    from \(appName, privacy: .public) \
                    in \(Int(Date().timeIntervalSince(started) * 1000))ms
                    """)

                await self?.showVariants(set)
            } catch is CancellationError {
                return
            } catch {
                await self?.showFailure(error.localizedDescription)
            }
        }
    }

    /// The personalised rewrite finished streaming.
    @MainActor
    private func finishPersonal(original: String, appName: String, started: Date) {
        panel.model.completePersonal()

        guard panel.model.personalIsChoosable else {
            showFailure("OpenAI returned nothing.")
            return
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Log.rewrite.notice("""
            Styled rewrite of \(original.count) chars \
            from \(appName, privacy: .public) in \(elapsed)ms
            """)

        statusMenu.setLastCapture(
            summary: "Ready in your style — press 1",
            preview: Self.preview(of: panel.model.personalText)
        )
    }

    /// Every variant has landed or failed.
    @MainActor
    private func finishStreaming(original: String, appName: String, started: Date) {
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        let usable = RephraseVariant.allCases.filter {
            panel.model.slots[$0]?.isChoosable ?? false
        }

        // Every one failed -- almost always a bad key or no network, so show the
        // reason rather than four empty rows.
        guard !usable.isEmpty else {
            let reason = RephraseVariant.allCases
                .compactMap { panel.model.slots[$0]?.error }
                .first ?? "OpenAI returned nothing."
            showFailure(reason)
            return
        }

        Log.rewrite.notice("""
            \(usable.count) of 4 variants for \(original.count) chars \
            from \(appName, privacy: .public) in \(elapsed)ms
            """)

        statusMenu.setLastCapture(
            summary: "\(usable.count) versions ready — press 1–4",
            preview: usable.first.flatMap { panel.model.slots[$0] }
                .map { Self.preview(of: $0.text) }
        )
    }

    @MainActor
    private func showVariants(_ set: RephraseSet) {
        panel.model.state = .ready(set)
        statusMenu.setLastCapture(
            summary: "\(set.available.count) versions ready — press 1–4",
            preview: set.available.first.map { Self.preview(of: $0.text) }
        )
    }

    @MainActor
    private func showFailure(_ message: String) {
        Log.rewrite.error("Rephrase failed: \(message, privacy: .public)")
        panel.model.state = .failed(message)
        statusMenu.setLastCapture(summary: "Failed — \(message)", preview: nil)
        statusMenu.flashTap(success: false)
    }

    /// The user picked one. Put it back where it came from.
    ///
    /// `label` is only for the log and the status menu -- "Polished", or
    /// "your voice" on the personalised path.
    @MainActor
    private func apply(label: String, text: String) {
        guard let field = pendingField else { return }

        // Read before dismissing: the panel owns the original text.
        let original = panel.model.currentOriginal

        // If the panel took focus for the follow-up box, give it back first --
        // the paste path needs the source app frontmost.
        if panel.model.isEditing {
            panel.endEditing(restoringFocusTo: field.pid)
        }

        // Close first: the panel sits over the text, and the paste path needs
        // the source app unobstructed.
        dismissPanel()

        let result = TextWriter.write(text, to: field, replacingSelection: pendingWasSelection)

        switch result {
        case .wroteViaAccessibility, .wroteViaPaste:
            let how: String
            switch result {
            case .wroteViaPaste: how = "paste"
            default: how = "accessibility"
            }
            Log.capture.notice(
                "Applied \(label, privacy: .public) via \(how, privacy: .public)"
            )

            let record = RephraseRecord(
                original: original,
                rewritten: text,
                appName: field.appName,
                accepted: true
            )
            history.add(record)
            statusMenu.setLastCapture(
                summary: "Applied \(label) in \(field.appName)",
                preview: Self.preview(of: text)
            )
            statusMenu.flashTap(success: true)

        case let .failed(message):
            Log.capture.error("Write failed: \(message, privacy: .public)")
            statusMenu.setLastCapture(summary: "Could not write — \(message)", preview: nil)
            statusMenu.flashTap(success: false)
        }

        settingsWindow.refreshIfVisible()
        pendingField = nil
    }

    /// Hand focus to the panel so the user can type an instruction.
    @MainActor
    private func beginEditing() {
        guard panel.isVisible, !panel.model.isEditing else { return }
        // The tap must stop swallowing keys, or typing "1" would apply a
        // rewrite instead of entering a character.
        eventTap?.wantsPanelKeys = false
        panel.beginEditing()
    }

    /// Rewrite again with an extra instruction from the user.
    ///
    /// Always returns a single result: they have just said what they want, so
    /// offering four guesses alongside it would be ignoring them.
    @MainActor
    private func refine(with instruction: String) {
        guard let apiKey = Keychain.readAPIKey(), pendingField != nil else { return }

        panel.endEditing(restoringFocusTo: pendingField?.pid)
        eventTap?.wantsPanelKeys = true

        let combined = Prompt.combining(style: Settings.style, instruction: instruction)
        let original = pendingOriginal
        let appName = pendingField?.appName ?? ""
        let model = Settings.model
        let started = Date()

        activeRephrase?.cancel()
        panel.model.beginPersonal(original: original)

        activeRephrase = Task { [weak self] in
            guard let self else { return }
            do {
                for try await delta in openAI.rephrasePersonal(
                    text: original, style: combined, model: model, apiKey: apiKey
                ) {
                    if Task.isCancelled { return }
                    await self.panel.model.appendPersonal(delta)
                }
                guard !Task.isCancelled else { return }
                await self.finishPersonal(
                    original: original, appName: appName, started: started
                )
            } catch is CancellationError {
                return
            } catch {
                await self.showFailure(error.localizedDescription)
            }
        }
    }

    // MARK: - Translation

    /// Write the captured text in another language.
    ///
    /// Built from `pendingOriginal` -- what the user actually typed -- and never
    /// from whichever rewrite happens to be on screen. Translating the English
    /// "Polished" version would put the message through two models before it
    /// reached its reader: twice the latency, and the user's own phrasing lost
    /// on the way, since the second model would be working from the first
    /// model's words rather than theirs.
    @MainActor
    private func translate(into language: TargetLanguage) {
        guard let apiKey = Keychain.readAPIKey(), pendingField != nil else { return }

        let original = pendingOriginal
        let appName = pendingField?.appName ?? ""
        let model = Settings.model
        let started = Date()

        activeRephrase?.cancel()
        panel.model.beginTranslating(into: language)

        activeRephrase = Task { [weak self] in
            guard let self else { return }
            do {
                for try await delta in openAI.translate(
                    text: original, to: language, model: model, apiKey: apiKey
                ) {
                    if Task.isCancelled { return }
                    await self.panel.model.appendTranslation(delta)
                }

                guard !Task.isCancelled else { return }
                await self.finishTranslation(
                    language: language, appName: appName, started: started
                )
            } catch is CancellationError {
                return
            } catch {
                await self.showFailure(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func finishTranslation(language: TargetLanguage, appName: String, started: Date) {
        panel.model.completeTranslation()

        guard panel.model.translationIsChoosable else {
            showFailure("OpenAI returned nothing.")
            return
        }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        Log.rewrite.notice("""
            Wrote \(language.rawValue, privacy: .public) for \(appName, privacy: .public) \
            in \(elapsed)ms
            """)

        statusMenu.setLastCapture(
            summary: "Ready in \(language.title) — press 1",
            preview: Self.preview(of: panel.model.translationText)
        )
    }

    /// Keep the tap's idea of the live number keys in step with the panel.
    @MainActor
    private func syncPanelDigits() {
        eventTap?.panelDigitCount = panel.model.liveDigitCount
    }

    @MainActor
    private func dismissPanel() {
        guard panel.isVisible else { return }
        panel.endEditing(restoringFocusTo: pendingField?.pid)
        panel.hide()
        eventTap?.wantsPanelKeys = false
        eventTap?.panelDigitCount = 0
        activeRephrase?.cancel()
    }

    /// Short, single-line excerpt for the menu.
    private static func preview(of text: String, limit: Int = 60) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)) + "…"
    }

    // MARK: - Permission

    private func requestPermission() {
        onboarding.show()
        waitForPermission()
    }

    /// Poll until access is granted, then start listening without a relaunch.
    private func waitForPermission() {
        guard permissionPoll == nil else { return }

        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] timer in
            guard Permissions.isTrusted else { return }
            timer.invalidate()
            self?.permissionPoll = nil
            Log.app.notice("Accessibility access granted -- starting listener")
            self?.startListening()
        }
    }
}
