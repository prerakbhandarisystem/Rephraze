import Foundation

/// One rephrase, as it happened.
public struct RephraseRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let original: String
    public let rewritten: String
    public let appName: String
    /// Did the user actually take the rewrite, or cancel it?
    public var accepted: Bool

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        original: String,
        rewritten: String,
        appName: String,
        accepted: Bool = false
    ) {
        self.id = id
        self.date = date
        self.original = original
        self.rewritten = rewritten
        self.appName = appName
        self.accepted = accepted
    }
}

/// Keeps a local record of every rephrase.
///
/// ## Treat this file as sensitive
/// It accumulates the text you typed into other applications. That makes it
/// genuinely useful — you can recover a rewrite you dismissed — and genuinely
/// private. So:
///
/// - it never leaves the machine
/// - the file is `0600`, readable only by you
/// - recording can be switched off entirely
/// - it can be cleared in one action
/// - it is capped, so it cannot grow without bound
public final class HistoryStore {

    /// Old entries are dropped past this. Enough to be useful, bounded enough
    /// that the file stays small and the exposure stays limited.
    public static let maxRecords = 500

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.prerak.rephraze.history")
    private var records: [RephraseRecord] = []

    /// User-facing switch. When off, nothing is written at all.
    public var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "historyEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "historyEnabled") }
    }

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rephraze", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        fileURL = base.appendingPathComponent("history.json")
        load()
    }

    // MARK: - Reading

    public var all: [RephraseRecord] {
        queue.sync { records }
    }

    public var count: Int {
        queue.sync { records.count }
    }

    public func search(_ term: String) -> [RephraseRecord] {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.original.lowercased().contains(needle)
                || $0.rewritten.lowercased().contains(needle)
                || $0.appName.lowercased().contains(needle)
        }
    }

    // MARK: - Writing

    public func add(_ record: RephraseRecord) {
        guard isEnabled else { return }
        queue.sync {
            records.insert(record, at: 0)
            if records.count > Self.maxRecords {
                records.removeLast(records.count - Self.maxRecords)
            }
            persist()
        }
    }

    /// Mark a record as accepted once the user takes the rewrite.
    public func markAccepted(id: UUID) {
        queue.sync {
            guard let index = records.firstIndex(where: { $0.id == id }) else { return }
            records[index].accepted = true
            persist()
        }
    }

    public func clear() {
        queue.sync {
            records.removeAll()
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([RephraseRecord].self, from: data)) ?? []
    }

    /// Caller must already hold `queue`.
    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]

        guard let data = try? encoder.encode(records) else { return }

        // Write, then lock down. Writing first and chmod-ing after would leave a
        // brief window where the file is world readable.
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public var fileLocation: URL { fileURL }
}
