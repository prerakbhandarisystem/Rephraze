import Foundation

/// Anonymous, opt-in usage reporting.
///
/// ## The rules this is built to
/// - **Off until asked for.** The default is off, and it stays off until
///   someone turns it on in Settings. There is no "we'll assume yes".
/// - **Nothing identifying.** A random install id, the app version, the OS
///   version, and the events in `UsageEvent` — which by construction cannot
///   carry text.
/// - **Never in the way.** Recording is a queue append. Sending happens on a
///   timer, off the main thread, and every failure is silent. A rephrase must
///   never be slower, or fail, because a dashboard wanted a number.
/// - **No endpoint, no collection.** With `AppInfo.usageEndpoint` unset, this
///   records nothing at all rather than quietly filling a file.
public final class Telemetry {

    /// How the batch actually travels. Injected so the queue can be tested
    /// without a network or a server.
    public typealias Transport = (URL, Data, @escaping (Bool) -> Void) -> Void

    /// Enough to survive a few days offline; small enough that the file stays
    /// trivial and a long outage cannot grow it without bound.
    public static let maxQueued = 500

    /// One POST does not carry the whole backlog. Keeps request bodies small
    /// and means a single rejected batch cannot block everything behind it.
    public static let maxPerBatch = 100

    /// Long enough that a busy session is one or two requests, short enough
    /// that a dashboard is not a day behind.
    public static let flushInterval: TimeInterval = 300

    private let fileURL: URL
    private let endpoint: URL?
    private let transport: Transport
    private let queue = DispatchQueue(label: "com.prerak.rephraze.telemetry")

    private var pending: [RecordedEvent] = []
    private var isSending = false
    private var timer: DispatchSourceTimer?

    // MARK: - Consent

    private static let enabledKey = "usageReportingEnabled"
    private static let installIDKey = "usageInstallID"

    /// Opt-in, and the default is the answer to "has anyone said yes yet".
    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            // Turning it off is retroactive: anything queued but not yet sent
            // is dropped, rather than going out after consent was withdrawn.
            if !newValue { clear() }
        }
    }

    /// A random UUID made here, stored here, and meaningless anywhere else.
    ///
    /// Not the hardware id, not the serial, not a hash of the login — those all
    /// survive a reinstall and can be cross-referenced with other software. A
    /// value we invent can be thrown away, which is what `resetInstallID` does.
    public static var installID: String {
        if let existing = UserDefaults.standard.string(forKey: installIDKey) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installIDKey)
        return fresh
    }

    /// Become a different install. Nothing already sent can be tied to what
    /// comes next.
    public func resetInstallID() {
        UserDefaults.standard.set(UUID().uuidString, forKey: Self.installIDKey)
        clear()
    }

    // MARK: - Life cycle

    public init(
        directory: URL? = nil,
        endpoint: URL? = AppInfo.usageEndpoint,
        transport: @escaping Transport = Telemetry.post
    ) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rephraze", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        self.fileURL = base.appendingPathComponent("usage-queue.json")
        self.endpoint = endpoint
        self.transport = transport
        load()
    }

    /// Begin the periodic flush. Separate from `init` so tests and previews can
    /// build one without a timer running.
    public func start() {
        guard timer == nil, isCollecting else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval)
        source.setEventHandler { [weak self] in self?.flush() }
        source.resume()
        timer = source
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// True when there is both consent and somewhere to send.
    public var isCollecting: Bool { isEnabled && endpoint != nil }

    // MARK: - Recording

    public func record(_ event: UsageEvent) {
        guard isCollecting else { return }
        queue.async {
            self.pending.append(RecordedEvent(event))
            if self.pending.count > Self.maxQueued {
                // Drop the oldest. A backlog that cannot be delivered is stale
                // long before it is interesting.
                self.pending.removeFirst(self.pending.count - Self.maxQueued)
            }
            self.persist()
        }
    }

    public var queuedCount: Int {
        queue.sync { pending.count }
    }

    /// Throw away anything not yet sent, and the file behind it.
    public func clear() {
        queue.sync {
            pending.removeAll()
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Sending

    /// Send what is queued, up to one batch. Safe to call at any time.
    public func flush() {
        queue.async { self.sendLocked() }
    }

    /// Caller must be on `queue`.
    private func sendLocked() {
        guard isCollecting, !isSending, let endpoint else { return }
        let batch = Array(pending.prefix(Self.maxPerBatch))
        guard !batch.isEmpty else { return }

        let payload = UsageBatch(
            installID: Self.installID,
            appVersion: AppInfo.version,
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            events: batch
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else {
            // Unencodable events would jam the queue behind them forever.
            pending.removeFirst(batch.count)
            persist()
            return
        }

        isSending = true
        transport(endpoint, data) { [weak self] delivered in
            guard let self else { return }
            self.queue.async {
                self.isSending = false
                guard delivered else { return }  // Keep them; try again later.
                self.pending.removeFirst(min(batch.count, self.pending.count))
                self.persist()
            }
        }
    }

    /// The real transport: one POST, no retry of its own, no callback into the
    /// app beyond "did that work".
    public static func post(to endpoint: URL, body: Data, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { _, response, error in
            guard error == nil, let http = response as? HTTPURLResponse else {
                return completion(false)
            }
            // A 4xx means the server will never accept this batch, so treat it
            // as delivered and move on rather than retrying it forever.
            completion((200..<300).contains(http.statusCode) || (400..<500).contains(http.statusCode))
        }.resume()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        pending = (try? decoder.decode([RecordedEvent].self, from: data)) ?? []
    }

    /// Caller must be on `queue`.
    private func persist() {
        guard !pending.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(pending) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public var fileLocation: URL { fileURL }

    /// Block until the work already queued has finished.
    ///
    /// Two passes, not one: delivering a batch enqueues its own completion, so
    /// a single barrier returns while that is still outstanding. Exists for
    /// tests — nothing in the app should ever wait on this.
    func settle() {
        queue.sync {}
        queue.sync {}
    }
}
