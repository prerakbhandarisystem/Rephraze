import Foundation

/// What a report is about.
///
/// Three kinds, not ten. The point of asking at all is that a subject line can
/// be triaged without opening the message; a longer list just makes the sender
/// hesitate over which box their problem belongs in.
public enum TicketKind: String, CaseIterable, Identifiable, Equatable {
    case bug
    case idea
    case question

    public var id: String { rawValue }

    /// Shown in the picker, in the sender's words rather than a support desk's.
    public var title: String {
        switch self {
        case .bug:      return "Something's broken"
        case .idea:     return "An idea"
        case .question: return "A question"
        }
    }

    /// Leads the subject line, so a full inbox sorts itself.
    public var tag: String {
        switch self {
        case .bug:      return "Bug"
        case .idea:     return "Idea"
        case .question: return "Question"
        }
    }

    /// Placeholder for the detail field, phrased as the thing most worth
    /// knowing about this kind of report.
    public var prompt: String {
        switch self {
        case .bug:      return "What did you do, what happened, and what did you expect instead?"
        case .idea:     return "What would you like it to do?"
        case .question: return "What would you like to know?"
        }
    }
}

/// The facts about this install that make a report actionable.
///
/// ## What is deliberately not in here
/// No captured text, no history entries, no API key — not even a masked one.
/// The app's promise is that what you type into other applications stays on
/// this Mac, and a support form is precisely where that promise gets broken by
/// accident. Every field below is a version number, a setting the user chose,
/// or a count.
///
/// The fields are a list rather than named properties so that the screen and
/// the email render from the same source. A field that shows up in one and not
/// the other is how "we only send X" stops being true.
public struct Diagnostics: Equatable {

    public struct Field: Equatable, Identifiable {
        public let label: String
        public let value: String
        public var id: String { label }

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public let fields: [Field]

    public init(fields: [Field]) {
        self.fields = fields
    }

    /// Plain `label: value` lines, which is all an email body can carry and all
    /// anyone reading a report actually wants.
    public var text: String {
        fields.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    /// Read the current state of the app.
    ///
    /// - Parameters:
    ///   - historyEnabled: whether rephrases are being recorded at all.
    ///   - historyCount: how many are on file. A count, never the entries.
    public static func current(historyEnabled: Bool, historyCount: Int) -> Diagnostics {
        Diagnostics(fields: [
            Field(label: "Rephraze", value: "\(AppInfo.version) (\(AppInfo.build))"),
            Field(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString),
            Field(
                label: "Accessibility",
                value: Permissions.isTrusted ? "granted" : "not granted"
            ),
            Field(label: "API key", value: Keychain.hasAPIKey ? "stored" : "missing"),
            Field(label: "Model", value: Settings.model),
            Field(
                label: "Parallel versions",
                value: Settings.useParallelVariants ? "on" : "off"
            ),
            Field(
                label: "Writing style",
                value: Settings.usesWritingStyle ? "in use" : "off"
            ),
            Field(
                label: "Translation",
                value: Settings.defaultLanguage?.title ?? "ask every time"
            ),
            Field(
                label: "History",
                value: historyEnabled ? "on, \(historyCount) recorded" : "off"
            ),
        ])
    }
}

/// A support request, on its way out as an email.
///
/// ## Why email and not a form that posts somewhere
/// The app has no server, and adding one to carry bug reports would mean
/// shipping a credential inside a distributed binary and standing up a service
/// whose only job is to receive a few messages a week. Handing the message to
/// the user's own mail client keeps the app serverless, and has a property no
/// in-app form does: nothing is sent until the sender looks at the whole
/// message and presses send themselves.
public struct SupportTicket: Equatable {

    /// `mailto:` has no formal length limit, but mail clients do — and the
    /// failure is silent, with nothing opening at all. Stay well under where
    /// anyone misbehaves, and say in the message that it was cut rather than
    /// dropping the end quietly.
    static let maxBodyLength = 6000

    public var kind: TicketKind
    public var summary: String
    public var detail: String
    public var includesDiagnostics: Bool
    public var diagnostics: Diagnostics

    public init(
        kind: TicketKind,
        summary: String,
        detail: String,
        includesDiagnostics: Bool,
        diagnostics: Diagnostics
    ) {
        self.kind = kind
        self.summary = summary
        self.detail = detail
        self.includesDiagnostics = includesDiagnostics
        self.diagnostics = diagnostics
    }

    /// A one-line summary is the whole requirement. Asking for more before the
    /// button works is how reports stop getting sent.
    public var isSendable: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var subject: String {
        "\(AppInfo.name) \(kind.tag): \(summary.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    public var body: String {
        let written = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard includesDiagnostics else { return Self.truncated(written, to: Self.maxBodyLength) }

        let footer = "\n\n---\n\(diagnostics.text)"
        return Self.truncated(written, to: Self.maxBodyLength - footer.count) + footer
    }

    private static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let note = "\n\n[cut here — the rest was too long to fit in an email link]"
        return String(text.prefix(max(0, limit - note.count))) + note
    }

    /// The `mailto:` URL that opens the user's mail client with this message
    /// composed and waiting.
    public func mailtoURL(to address: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        // Built by hand rather than through `queryItems`, which percent-encodes
        // with a set that leaves `&` and `+` alone — so the first ampersand
        // someone types would split their report in half.
        components.percentEncodedQuery =
            "subject=\(Self.encode(subject))&body=\(Self.encode(body))"
        return components.url
    }

    /// The whole message as text, for when there is no mail client to hand it
    /// to and the clipboard is the only way not to lose what was written.
    public func plainText(to address: String) -> String {
        "To: \(address)\nSubject: \(subject)\n\n\(body)"
    }

    private static let queryAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        // Query delimiters, plus `+`, which some clients decode back as a space.
        set.remove(charactersIn: "&=+?#")
        return set
    }()

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? ""
    }
}
