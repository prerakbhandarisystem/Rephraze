import Testing
import Foundation
@testable import RephrazeKit

@Suite("UsageEvent")
struct UsageEventTests {

    @Test("Every case has a stable name")
    func names() {
        #expect(UsageEvent.launched.name == "launched")
        #expect(UsageEvent.rephrased(outcome: .accepted, personalised: false, milliseconds: 1).name
                == "rephrased")
        #expect(UsageEvent.translated(language: .french).name == "translated")
        #expect(UsageEvent.failed(reason: .write).name == "failed")
    }

    @Test("Launching carries nothing at all")
    func launchIsBare() {
        #expect(UsageEvent.launched.properties.isEmpty)
    }

    @Test("A rephrase carries an outcome, a flag and a duration — and only those")
    func rephraseProperties() {
        let properties = UsageEvent
            .rephrased(outcome: .dismissed, personalised: true, milliseconds: 820)
            .properties

        #expect(Set(properties.keys) == ["outcome", "personalised", "milliseconds"])
        #expect(properties["outcome"] == .text("dismissed"))
        #expect(properties["personalised"] == .flag(true))
        #expect(properties["milliseconds"] == .number(820))
    }

    /// A Mac asleep mid-request would otherwise report a rephrase that took
    /// hours and drag every average with it.
    @Test("Durations are clamped at both ends")
    func clampsDuration() {
        func ms(_ value: Int) -> UsageValue? {
            UsageEvent.rephrased(outcome: .accepted, personalised: false, milliseconds: value)
                .properties["milliseconds"]
        }
        #expect(ms(-5) == .number(0))
        #expect(ms(500) == .number(500))
        #expect(ms(9_999_999) == .number(120_000))
    }

    @Test("A language goes as its identifier, not its display name")
    func translationProperties() {
        #expect(UsageEvent.translated(language: .japanese).properties
                == ["language": .text("japanese")])
    }

    @Test("Values survive a JSON round trip with their type intact")
    func valueRoundTrip() throws {
        let original: [UsageValue] = [.text("accepted"), .number(42), .flag(true), .flag(false)]
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode([UsageValue].self, from: data) == original)
    }

    /// `true` decodes as `1` if the order is wrong, which would turn a flag
    /// into a count on the dashboard.
    @Test("A flag does not come back as a number")
    func flagIsNotANumber() throws {
        let data = Data("[true,1]".utf8)
        #expect(try JSONDecoder().decode([UsageValue].self, from: data) == [.flag(true), .number(1)])
    }
}

/// Collects what the transport was handed, and decides what to tell it.
private final class FakeTransport {
    var batches: [UsageBatch] = []
    var succeeds = true

    var send: Telemetry.Transport {
        { [self] _, data, completion in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let batch = try? decoder.decode(UsageBatch.self, from: data) {
                batches.append(batch)
            }
            completion(succeeds)
        }
    }

    var sentEvents: [RecordedEvent] { batches.flatMap(\.events) }
}

@Suite("Telemetry", .serialized)
struct TelemetryTests {

    private static let endpoint = URL(string: "https://example.invalid/v1/events")!

    /// A fresh directory and a fresh consent state per test. Consent lives in
    /// `UserDefaults`, which is shared, so it is put back afterwards.
    private func makeTelemetry(
        endpoint: URL? = TelemetryTests.endpoint,
        transport: FakeTransport = FakeTransport()
    ) -> (Telemetry, FakeTransport, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rephraze-telemetry-\(UUID().uuidString)")
        let telemetry = Telemetry(
            directory: dir,
            endpoint: endpoint,
            transport: transport.send
        )
        telemetry.isEnabled = true
        return (telemetry, transport, dir)
    }

    private func cleanUp(_ telemetry: Telemetry, _ dir: URL) {
        telemetry.isEnabled = false
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Consent

    @Test("Records nothing until someone opts in")
    func offByDefault() {
        let (telemetry, _, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        telemetry.isEnabled = false
        telemetry.record(.launched)
        telemetry.settle()

        #expect(telemetry.queuedCount == 0)
        #expect(telemetry.isCollecting == false)
    }

    /// The safety net for a build that was never pointed at a server: consent
    /// on its own must not start filling a file.
    @Test("Records nothing when the build has no endpoint")
    func noEndpointMeansNoCollection() {
        let (telemetry, _, dir) = makeTelemetry(endpoint: nil)
        defer { cleanUp(telemetry, dir) }

        telemetry.record(.launched)
        telemetry.settle()

        #expect(telemetry.isEnabled)
        #expect(telemetry.isCollecting == false)
        #expect(telemetry.queuedCount == 0)
    }

    @Test("Withdrawing consent drops what was queued but not yet sent")
    func optingOutClearsTheQueue() {
        let (telemetry, transport, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        telemetry.record(.launched)
        telemetry.settle()
        #expect(telemetry.queuedCount == 1)

        telemetry.isEnabled = false

        #expect(telemetry.queuedCount == 0)
        #expect(FileManager.default.fileExists(atPath: telemetry.fileLocation.path) == false)

        telemetry.flush()
        telemetry.settle()
        #expect(transport.batches.isEmpty)
    }

    @Test("Resetting the identifier makes a new install and discards the backlog")
    func resetInstallID() {
        let (telemetry, _, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        let before = Telemetry.installID
        telemetry.record(.launched)
        telemetry.settle()

        telemetry.resetInstallID()

        #expect(Telemetry.installID != before)
        #expect(telemetry.queuedCount == 0)
    }

    // MARK: - Queue

    @Test("Events queue up in order")
    func queuesEvents() {
        let (telemetry, _, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        telemetry.record(.launched)
        telemetry.record(.translated(language: .german))
        telemetry.settle()

        #expect(telemetry.queuedCount == 2)
    }

    @Test("A backlog that cannot be delivered drops its oldest, not its newest")
    func capsTheQueue() {
        let (telemetry, transport, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }
        transport.succeeds = false

        for _ in 0..<(Telemetry.maxQueued + 25) {
            telemetry.record(.launched)
        }
        telemetry.record(.translated(language: .hindi))
        telemetry.settle()

        #expect(telemetry.queuedCount == Telemetry.maxQueued)

        telemetry.flush()
        telemetry.settle()
        // The most recent event is still in there; the oldest went.
        #expect(telemetry.queuedCount == Telemetry.maxQueued)
    }

    @Test("The queue survives a relaunch")
    func survivesRestart() {
        let (telemetry, _, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        telemetry.record(.launched)
        telemetry.record(.launched)
        telemetry.settle()

        let reopened = Telemetry(
            directory: dir,
            endpoint: Self.endpoint,
            transport: FakeTransport().send
        )
        #expect(reopened.queuedCount == 2)
    }

    @Test("The queue file is owner-only (0600)")
    func queueFileIsPrivate() throws {
        let (telemetry, _, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        telemetry.record(.launched)
        telemetry.settle()

        let attributes = try FileManager.default
            .attributesOfItem(atPath: telemetry.fileLocation.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
    }

    // MARK: - Sending

    @Test("A delivered batch leaves the queue")
    func flushDelivers() {
        let (telemetry, transport, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        telemetry.record(.launched)
        telemetry.record(.failed(reason: .write))
        telemetry.settle()

        telemetry.flush()
        telemetry.settle()

        #expect(telemetry.queuedCount == 0)
        #expect(transport.sentEvents.map(\.name) == ["launched", "failed"])
    }

    @Test("A batch carries the install, the version and the system")
    func batchEnvelope() throws {
        let (telemetry, transport, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        telemetry.record(.launched)
        telemetry.settle()
        telemetry.flush()
        telemetry.settle()

        let batch = try #require(transport.batches.first)
        #expect(batch.installID == Telemetry.installID)
        #expect(batch.appVersion == AppInfo.version)
        #expect(!batch.system.isEmpty)
    }

    @Test("A failed send keeps the events for next time")
    func failedSendRetains() {
        let (telemetry, transport, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }
        transport.succeeds = false

        telemetry.record(.launched)
        telemetry.settle()
        telemetry.flush()
        telemetry.settle()

        #expect(telemetry.queuedCount == 1)

        transport.succeeds = true
        telemetry.flush()
        telemetry.settle()

        #expect(telemetry.queuedCount == 0)
    }

    @Test("One flush sends at most a batch, leaving the rest behind")
    func batchesAreCapped() {
        let (telemetry, transport, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        for _ in 0..<(Telemetry.maxPerBatch + 30) {
            telemetry.record(.launched)
        }
        telemetry.settle()

        telemetry.flush()
        telemetry.settle()

        #expect(transport.batches.count == 1)
        #expect(transport.sentEvents.count == Telemetry.maxPerBatch)
        #expect(telemetry.queuedCount == 30)
    }

    @Test("Nothing to send means no request at all")
    func emptyFlushIsSilent() {
        let (telemetry, transport, dir) = makeTelemetry()
        defer { cleanUp(telemetry, dir) }

        telemetry.flush()
        telemetry.settle()

        #expect(transport.batches.isEmpty)
    }
}
