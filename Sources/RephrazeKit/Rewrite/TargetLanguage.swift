import Foundation

/// The languages Rephraze can write in.
///
/// Ten, chosen by how much text is actually typed in them on a Mac rather than
/// by speaker count alone. That is why Bengali and Urdu -- both comfortably
/// inside the global top ten by speakers -- are not here, and German and
/// Japanese are: this app sits in Slack and Mail, and that is a different
/// population from the world's.
///
/// The order is fixed and must stay fixed. It is the number you press, and a
/// list that reordered itself by recent use would move a language under the
/// user's finger between reading "6" and pressing it.
public enum TargetLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english
    case spanish
    case chinese
    case hindi
    case arabic
    case french
    case portuguese
    case russian
    case german
    case japanese

    public var id: String { rawValue }

    /// What we call it in the UI, in English.
    public var title: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Spanish"
        case .chinese:    return "Chinese"
        case .hindi:      return "Hindi"
        case .arabic:     return "Arabic"
        case .french:     return "French"
        case .portuguese: return "Portuguese"
        case .russian:    return "Russian"
        case .german:     return "German"
        case .japanese:   return "Japanese"
        }
    }

    /// The language's own name for itself, shown beside the English one.
    ///
    /// Worth the row space: someone scanning for the language they are about to
    /// write in finds "日本語" faster than "Japanese", because it is the script
    /// they are already thinking in.
    public var endonym: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Español"
        case .chinese:    return "简体中文"
        case .hindi:      return "हिन्दी"
        case .arabic:     return "العربية"
        case .french:     return "Français"
        case .portuguese: return "Português"
        case .russian:    return "Русский"
        case .german:     return "Deutsch"
        case .japanese:   return "日本語"
        }
    }

    /// How the language is named to the model.
    ///
    /// Three of these need a variety pinned or the model picks one for you, and
    /// picking wrong is not a subtle error: Traditional characters are unreadable
    /// to a mainland reader in the sense that matters, and European Portuguese
    /// lands as stilted in São Paulo.
    public var promptName: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Spanish"
        case .chinese:    return "Simplified Chinese (zh-Hans, as written in mainland China)"
        case .hindi:      return "Hindi, in Devanagari script"
        case .arabic:     return "Modern Standard Arabic"
        case .french:     return "French"
        case .portuguese: return "Brazilian Portuguese (pt-BR)"
        case .russian:    return "Russian"
        case .german:     return "German"
        case .japanese:   return "Japanese"
        }
    }

    /// Written right to left, so the result has to be laid out that way too.
    public var isRightToLeft: Bool { self == .arabic }

    /// The key that picks this one.
    ///
    /// Ten languages onto ten keys: 1-9 and then 0, exactly as the number row
    /// is laid out, so the tenth is where your hand already expects it.
    public var shortcutDigit: Int {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return index == 9 ? 0 : index + 1
    }

    /// The language a digit selects, or nil if that key means nothing here.
    public static func forDigit(_ digit: Int) -> TargetLanguage? {
        allCases.first { $0.shortcutDigit == digit }
    }
}
