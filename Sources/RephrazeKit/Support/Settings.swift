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

    // MARK: - Your voice

    /// How this person wants to sound, in their own words.
    ///
    /// Free text rather than a set of switches. "Professional" and "friendly"
    /// are someone else's categories; the thing that makes writing sound like
    /// you is too specific to fit in a menu -- how long your sentences run,
    /// whether you swear, that you never use exclamation marks.
    public static var voice: String {
        get { defaults.string(forKey: Key.voice) ?? "" }
        set { defaults.set(newValue, forKey: Key.voice) }
    }

    /// Switch the personal voice off without throwing away what was written.
    public static var voiceEnabled: Bool {
        get { defaults.object(forKey: Key.voiceEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.voiceEnabled) }
    }

    /// The wizard answers behind `voice`, kept so the questions can be resumed
    /// and revised later rather than restarted from nothing.
    ///
    /// A plain string-to-string dictionary, which UserDefaults stores natively.
    public static var voiceAnswers: [String: String] {
        get { defaults.dictionary(forKey: Key.voiceAnswers) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.voiceAnswers) }
    }

    /// True when a rephrase should return one personalised rewrite instead of
    /// the four generic ones.
    public static var usesPersonalVoice: Bool {
        voiceEnabled && !voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
