import Foundation

/// Small, non-secret preferences. The API key lives in the Keychain instead.
public enum Settings {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let model = "model"
    }

    /// Chosen for speed and cost: a rephrase is a short, easy task and the whole
    /// point is that it feels instant.
    public static let defaultModel = "gpt-4o-mini"

    public static var model: String {
        get { defaults.string(forKey: Key.model) ?? defaultModel }
        set { defaults.set(newValue, forKey: Key.model) }
    }
}
