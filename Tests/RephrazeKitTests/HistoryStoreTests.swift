import Testing
import Foundation
@testable import RephrazeKit

@Suite("HistoryStore", .serialized)
struct HistoryStoreTests {

    /// Each test gets its own directory so they cannot see each other's files.
    private func makeStore() -> (HistoryStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rephraze-test-\(UUID().uuidString)")
        let store = HistoryStore(directory: dir)
        store.isEnabled = true
        return (store, dir)
    }

    private func record(_ original: String, _ rewritten: String, app: String = "TestApp")
        -> RephraseRecord {
        RephraseRecord(original: original, rewritten: rewritten, appName: app)
    }

    @Test("Starts empty")
    func startsEmpty() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.count == 0)
    }

    @Test("Newest entries come first")
    func newestFirst() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.add(record("first", "1"))
        store.add(record("second", "2"))

        #expect(store.all.first?.original == "second")
        #expect(store.count == 2)
    }

    @Test("Survives a reload from disk")
    func persistsAcrossInstances() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.add(record("remember me", "rewritten"))

        let reopened = HistoryStore(directory: dir)
        #expect(reopened.count == 1)
        #expect(reopened.all.first?.original == "remember me")
    }

    /// Unbounded growth would mean an ever-larger file of everything you typed.
    @Test("Caps at maxRecords, dropping the oldest")
    func capsAtLimit() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        for i in 0...(HistoryStore.maxRecords + 10) {
            store.add(record("entry \(i)", "r"))
        }

        #expect(store.count == HistoryStore.maxRecords)
        #expect(store.all.first?.original == "entry \(HistoryStore.maxRecords + 10)")
        #expect(store.all.contains { $0.original == "entry 0" } == false)
    }

    @Test("Search matches original, rewrite, and app name")
    func searchMatchesAllFields() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.add(record("hello world", "greetings", app: "Slack"))
        store.add(record("nothing here", "empty", app: "Mail"))

        #expect(store.search("hello").count == 1)
        #expect(store.search("greetings").count == 1)
        #expect(store.search("slack").count == 1)
        #expect(store.search("nope").isEmpty)
    }

    @Test("Search is case insensitive and an empty term returns everything")
    func searchCaseAndEmpty() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.add(record("Hello World", "x"))
        #expect(store.search("HELLO").count == 1)
        #expect(store.search("   ").count == 1)
    }

    @Test("Accepting a rewrite is recorded")
    func markAccepted() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let entry = record("a", "b")
        store.add(entry)
        #expect(store.all.first?.accepted == false)

        store.markAccepted(id: entry.id)
        #expect(store.all.first?.accepted == true)
    }

    @Test("Clear removes everything, including the file")
    func clearRemovesAll() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.add(record("a", "b"))
        store.clear()

        #expect(store.count == 0)
        #expect(FileManager.default.fileExists(atPath: store.fileLocation.path) == false)
    }

    /// The off switch has to actually mean off.
    @Test("Nothing is written when recording is disabled")
    func disabledWritesNothing() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir); store.isEnabled = true }

        store.isEnabled = false
        store.add(record("secret", "text"))

        #expect(store.count == 0)
        #expect(FileManager.default.fileExists(atPath: store.fileLocation.path) == false)
    }

    /// The file is a log of what you typed elsewhere; it must not be readable
    /// by other users on the machine.
    @Test("History file is owner-only (0600)")
    func fileIsOwnerOnly() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.add(record("a", "b"))

        let attrs = try FileManager.default.attributesOfItem(atPath: store.fileLocation.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)
    }
}
