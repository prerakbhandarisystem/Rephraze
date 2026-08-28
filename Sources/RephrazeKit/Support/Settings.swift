import Foundation

/// Small, non-secret preferences. The API key lives in the Keychain instead.
public enum Settings {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let model = "model"
        static let parallelVariants = "parallelVariants"
        static let voice = "voiceInstructions"
        static let voiceEnabled = "voiceEnabled"
        static let voiceAnswers = "voiceAnswers"
        static let defaultLanguage = "defaultLanguage"
        static let replyAddress = "supportReplyAddress"
        static let triggerKey = "triggerKey"
        static let doubleTapWindow = "doubleTapWindow"
        static let showsInDock = "showsInDock"
        static let panelFollowsFullScreen = "panelFollowsFullScreen"
        static let soundOnReady = "soundOnReady"
        static let soundOnFailure = "soundOnFailure"
        static let notifyOnFailure = "notifyOnFailure"
        static let notifyWhenLow = "notifyWhenLow"
    }

    /// Chosen for speed and cost: a rephrase is a short, easy task and the whole
    /// point is that it feels instant.
    public static let defaultModel = "gpt-4o-mini"

    public static var model: String {
        get { defaults.string(forKey: Key.model) ?? defaultModel }
        set { defaults.set(newValue, forKey: Key.model) }
    }

    /// Four concurrent calls instead of one combined call.
    ///
    /// On by default: it puts the first rewrite on screen roughly three times
    /// sooner, for about 20-30% more tokens. The single-call path stays
    /// available because it is cheaper, and because having both makes the two
    /// comparable on real text.
    public static var useParallelVariants: Bool {
        get { defaults.object(forKey: Key.parallelVariants) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.parallelVariants) }
    }

    /// The address the last support report asked for a reply at.
    ///
    /// Remembered so that filing a second report is one line of typing rather
    /// than the same address again. Kept here rather than in the Keychain: it
    /// is the address they typed into a form to be written back at, not a
    /// secret.
    public static var replyAddress: String {
        get { defaults.string(forKey: Key.replyAddress) ?? "" }
        set { defaults.set(newValue, forKey: Key.replyAddress) }
    }

    // MARK: - The shortcut

    /// The modifier you tap twice to summon a rewrite.
    ///
    /// Option by default, and the default is load-bearing: macOS binds a
    /// double-tap of either Command key to Siri, so ⌘⌘ opens Siri
    /// instead of us. Command is still offered because someone who has turned
    /// Siri off should be allowed to have it.
    public static var triggerKey: TriggerKey {
        get {
            defaults.string(forKey: Key.triggerKey)
                .flatMap(TriggerKey.init(rawValue:)) ?? .option
        }
        set { defaults.set(newValue.rawValue, forKey: Key.triggerKey) }
    }

    /// How long the second tap has to arrive.
    ///
    /// Adjustable because the right number is a property of the hand, not of
    /// the app. Too short and a deliberate double-tap is read as two stray
    /// ones; too long and reaching for ⌘C twice in a row fires a rewrite
    /// nobody asked for.
    public static var doubleTapWindow: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.doubleTapWindow)
            // 0 is also what UserDefaults returns for "never set".
            return stored > 0 ? stored : DoubleTapDetector.defaultWindow
        }
        set { defaults.set(newValue, forKey: Key.doubleTapWindow) }
    }

    // MARK: - How the app sits in the system

    /// Whether the app keeps a Dock icon.
    ///
    /// Off by default: this is a menu bar app, and a second permanent icon for
    /// something you summon with a keypress is clutter. On for the people who
    /// navigate by Dock and want somewhere to click.
    public static var showsInDock: Bool {
        get { defaults.object(forKey: Key.showsInDock) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showsInDock) }
    }

    /// Whether the rewrite panel is allowed to appear over a full-screen app.
    ///
    /// On by default. People write in full screen -- that is rather the point
    /// of full screen -- and a panel that refuses to show up there would make
    /// the shortcut look broken in exactly the apps it is most wanted in.
    public static var panelFollowsFullScreen: Bool {
        get { defaults.object(forKey: Key.panelFollowsFullScreen) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.panelFollowsFullScreen) }
    }

    // MARK: - Sound and notifications

    /// A short tone when the first rewrite lands.
    ///
    /// Off by default, and every switch below it too. The app arrives silent
    /// because it interrupts you often and by design; a noise on every rewrite
    /// is a noise dozens of times a day. Anyone who wants the confirmation can
    /// have it, but nobody is given it without asking.
    public static var soundOnReady: Bool {
        get { defaults.bool(forKey: Key.soundOnReady) }
        set { defaults.set(newValue, forKey: Key.soundOnReady) }
    }

    /// A lower tone when a rewrite fails.
    public static var soundOnFailure: Bool {
        get { defaults.bool(forKey: Key.soundOnFailure) }
        set { defaults.set(newValue, forKey: Key.soundOnFailure) }
    }

    /// A notification when a rewrite fails.
    public static var notifyOnFailure: Bool {
        get { defaults.bool(forKey: Key.notifyOnFailure) }
        set { defaults.set(newValue, forKey: Key.notifyOnFailure) }
    }

    /// A notification, once, when the free rewrites start running out.
    public static var notifyWhenLow: Bool {
        get { defaults.bool(forKey: Key.notifyWhenLow) }
        set { defaults.set(newValue, forKey: Key.notifyWhenLow) }
    }

    // MARK: - Your voice

    /// How this person wants to sound, in their own words.
    ///
    /// Free text rather than a set of switches. "Professional" and "friendly"
    /// are someone else's categories; the thing that makes writing sound like
    /// you is too specific to fit in a menu -- how long your sentences run,
    /// whether you swear, that you never use exclamation marks.
    public static var style: String {
        get { defaults.string(forKey: Key.voice) ?? "" }
        set { defaults.set(newValue, forKey: Key.voice) }
    }

    /// Switch the personal voice off without throwing away what was written.
    public static var styleEnabled: Bool {
        get { defaults.object(forKey: Key.voiceEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.voiceEnabled) }
    }

    /// The wizard answers behind `voice`, kept so the questions can be resumed
    /// and revised later rather than restarted from nothing.
    ///
    /// A plain string-to-string dictionary, which UserDefaults stores natively.
    public static var styleAnswers: VoiceAnswers {
        get { defaults.dictionary(forKey: Key.voiceAnswers) as? VoiceAnswers ?? [:] }
        set { defaults.set(newValue, forKey: Key.voiceAnswers) }
    }

    // MARK: - Translation

    /// The language ⌥T writes in without asking first.
    ///
    /// `nil` means ask every time, and that is the default. Most people write
    /// into one other language most days, but we do not know which one until
    /// they say so -- and guessing it from the system locale would be wrong for
    /// precisely the bilingual users this exists for, whose Mac is in English
    /// because their Mac is in English.
    public static var defaultLanguage: TargetLanguage? {
        get {
            defaults.string(forKey: Key.defaultLanguage)
                .flatMap(TargetLanguage.init(rawValue:))
        }
        set { defaults.set(newValue?.rawValue, forKey: Key.defaultLanguage) }
    }

    /// True when a rephrase should return one personalised rewrite instead of
    /// the four generic ones.
    public static var usesWritingStyle: Bool {
        styleEnabled && !style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
