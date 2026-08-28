import Foundation

/// A writing style, packaged so it can leave this Mac.
///
/// ## Why a file and not an account
/// Rephraze has no server and no logins -- your key talks to OpenAI directly,
/// and nothing about you is stored anywhere we could look. That rules out a
/// team in the usual sense, but not the thing a team actually wants from one:
/// everybody's rewrites sounding like the same house.
///
/// So a team here is a file. One person answers the questions, exports the
/// result, and everyone else imports it. It travels over whatever the team
/// already uses, it can be read before it is trusted, and nobody has to hand
/// their writing to a third party to share how they write.
public struct StyleProfile: Codable, Equatable {

    /// Bumped only if the shape changes in a way an older build cannot read.
    /// Present from version one so that there is somewhere to check.
    public static let currentVersion = 1

    public var version: Int
    /// What this voice is called, e.g. "Support replies". Free text, because
    /// the person exporting knows what it is for and we do not.
    public var name: String
    /// The description the rewrites are actually written against.
    public var describedStyle: String
    /// The wizard answers behind it, so the recipient can revise the voice
    /// rather than only inherit it.
    public var answers: VoiceAnswers
    public var exportedAt: Date
    /// The build it came from. Useful in a bug report, useless otherwise --
    /// deliberately not the install identifier, which would make a shared file
    /// into a way of tracking who sent it.
    public var exportedBy: String

    public init(
        version: Int = StyleProfile.currentVersion,
        name: String,
        describedStyle: String,
        answers: VoiceAnswers,
        exportedAt: Date = Date(),
        exportedBy: String = "\(AppInfo.name) \(AppInfo.version)"
    ) {
        self.version = version
        self.name = name
        self.describedStyle = describedStyle
        self.answers = answers
        self.exportedAt = exportedAt
        self.exportedBy = exportedBy
    }

    /// The extension a profile is saved under. Not `.json`: it is a Rephraze
    /// document, and naming it so keeps a folder of them legible.
    public static let fileExtension = "rephrazestyle"

    /// A filename that says what it holds without needing to be opened.
    public var suggestedFilename: String {
        let stem = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = stem.isEmpty ? "Writing style" : stem
        return "\(safe).\(Self.fileExtension)"
    }

    public enum ProfileError: Error, LocalizedError {
        case unreadable
        case tooNew(Int)

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file is not a Rephraze writing style."
            case let .tooNew(version):
                return "That style was made by a newer version of Rephraze (format \(version))."
            }
        }
    }

    // MARK: - On disk

    /// Pretty-printed with sorted keys on purpose.
    ///
    /// These files get committed to repositories and pasted into chat threads.
    /// A readable one can be reviewed before it is trusted, and two exports of
    /// the same voice produce the same bytes, so a diff shows what changed
    /// rather than that something did.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> StyleProfile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let profile = try? decoder.decode(StyleProfile.self, from: data) else {
            throw ProfileError.unreadable
        }
        // Refuse forwards rather than importing half of it. A profile whose
        // extra fields we silently drop is a voice that quietly differs from
        // the one the sender is using.
        guard profile.version <= currentVersion else {
            throw ProfileError.tooNew(profile.version)
        }
        return profile
    }

    // MARK: - This Mac

    /// Package up the style currently in use.
    public static func current(named name: String) -> StyleProfile {
        StyleProfile(
            name: name,
            describedStyle: Settings.style,
            answers: Settings.styleAnswers
        )
    }

    /// Make this profile the style in use.
    ///
    /// Switched on as part of applying it. Someone who has just imported a
    /// voice meant it to be the voice, and leaving it stored-but-off would look
    /// exactly like the import having failed.
    public func apply() {
        Settings.style = describedStyle
        Settings.styleAnswers = answers
        Settings.styleEnabled = true
    }
}
