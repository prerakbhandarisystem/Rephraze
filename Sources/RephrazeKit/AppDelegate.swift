import AppKit

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

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu.install()
        statusMenu.isHotkeyRunning = { [weak self] in self?.eventTap?.isRunning ?? false }
        statusMenu.onRequestPermission = { [weak self] in self?.requestPermission() }
        statusMenu.triggerName = { [weak self] in
            self?.trigger.displayName ?? TriggerKey.command.displayName
        }

        statusMenu.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        settingsWindow.history = history
        onboarding.onGranted = { [weak self] in self?.startListening() }

        // No window at all is the right look once this works -- but on a first
        // launch with no permission it reads as "nothing happened". Say so.
        Log.app.notice("Launched. Accessibility trusted = \(Permissions.isTrusted)")
        if Permissions.isTrusted {
            startListening()
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
            // Single taps only mean something while the panel is open, where
            // they accept the rewrite. Ignored otherwise -- people tap ⌘ alone
            // by accident constantly.
            break

        case .escape:
            // Only meaningful once the panel exists (Step 4).
            break
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

    /// Send the captured text to OpenAI and stream the rewrite back.
    private func rephrase(_ capture: CapturedText) {
        guard let apiKey = Keychain.readAPIKey() else {
            Log.rewrite.notice("No API key stored")
            statusMenu.setLastCapture(
                summary: "No API key — open Settings to add one",
                preview: nil
            )
            settingsWindow.show()
            return
        }

        // Only one in flight. A second trigger replaces the first rather than
        // racing it, so two rewrites can never land in the same box.
        activeRephrase?.cancel()

        let original = capture.text
        let appName = capture.field.appName
        let model = Settings.model

        activeRephrase = Task { [weak self] in
            var assembled = ""
            do {
                let stream = self?.openAI.rephrase(text: original, model: model, apiKey: apiKey)
                guard let stream else { return }

                for try await delta in stream {
                    assembled += delta
                }

                guard !Task.isCancelled else { return }

                let rewritten = assembled.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rewritten.isEmpty else {
                    await self?.reportRephraseFailure("OpenAI returned nothing")
                    return
                }

                // Character counts only -- never the text itself.
                Log.rewrite.notice("""
                    Rewrote \(original.count) chars into \(rewritten.count)                     for \(appName, privacy: .public)
                    """)

                await self?.finishRephrase(
                    original: original,
                    rewritten: rewritten,
                    appName: appName
                )
            } catch is CancellationError {
                return
            } catch {
                await self?.reportRephraseFailure(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func finishRephrase(original: String, rewritten: String, appName: String) {
        history.add(RephraseRecord(
            original: original,
            rewritten: rewritten,
            appName: appName
        ))

        // Step 4 replaces this with the floating panel that puts the text back.
        statusMenu.setLastCapture(
            summary: "Rewrote \(original.count) → \(rewritten.count) chars (\(appName))",
            preview: Self.preview(of: rewritten)
        )
        statusMenu.flashTap(success: true)
    }

    @MainActor
    private func reportRephraseFailure(_ message: String) {
        Log.rewrite.error("Rephrase failed: \(message, privacy: .public)")
        statusMenu.setLastCapture(summary: "Failed — \(message)", preview: nil)
        statusMenu.flashTap(success: false)
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
