import Testing
import Foundation
@testable import RephrazeKit

@Suite("The rewrite allowance")
struct UsageQuotaTests {

    /// Its own defaults domain per test, so a run never reads or writes the
    /// real preferences -- and two tests cannot see each other's counts.
    private func quota() -> UsageQuota {
        let suite = "quota-test-\(UUID().uuidString)"
        return UsageQuota(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test("A fresh install has the whole allowance")
    func startsFull() {
        let q = quota()
        #expect(q.used == 0)
        #expect(q.remaining == UsageQuota.allowance)
        #expect(!q.isExhausted)
        #expect(!q.isRunningLow)
    }

    @Test("Each applied rewrite spends one")
    func countsUp() {
        let q = quota()
        q.recordApplied()
        q.recordApplied()
        q.recordApplied()

        #expect(q.used == 3)
        #expect(q.remaining == UsageQuota.allowance - 3)
    }

    @Test("The count survives being read through a new instance")
    func persists() {
        let suite = "quota-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        UsageQuota(defaults: defaults).recordApplied()

        #expect(UsageQuota(defaults: defaults).used == 1)
    }

    @Test("Running low starts exactly at the low-water mark")
    func warnsOnlyNearTheEnd() {
        let q = quota()
        for _ in 0..<(UsageQuota.allowance - UsageQuota.lowWaterMark - 1) {
            q.recordApplied()
        }
        #expect(!q.isRunningLow, "one above the mark should still be quiet")

        q.recordApplied()
        #expect(q.isRunningLow)
        #expect(q.remaining == UsageQuota.lowWaterMark)
    }

    @Test("Exhausted at exactly the allowance, not before")
    func exhaustsOnTheLastOne() {
        let q = quota()
        for _ in 0..<(UsageQuota.allowance - 1) { q.recordApplied() }
        #expect(!q.isExhausted)
        #expect(q.remaining == 1)

        q.recordApplied()
        #expect(q.isExhausted)
        #expect(q.remaining == 0)
    }

    /// Nothing blocks at the allowance, so going past it is reachable, and how
    /// far past is the number worth knowing.
    @Test("Going over keeps counting, and remaining floors at zero")
    func countsPastTheAllowance() {
        let q = quota()
        for _ in 0..<(UsageQuota.allowance + 7) { q.recordApplied() }

        #expect(q.used == UsageQuota.allowance + 7)
        #expect(q.remaining == 0)
        #expect(q.isExhausted)
    }

    @Test("A negative count on disk is not trusted")
    func ignoresNonsenseOnDisk() {
        let suite = "quota-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(-5, forKey: "rewritesApplied")

        let q = UsageQuota(defaults: defaults)
        #expect(q.used == 0)
        #expect(q.remaining == UsageQuota.allowance)
    }

    @Test("Reset puts the whole allowance back")
    func resets() {
        let q = quota()
        for _ in 0..<12 { q.recordApplied() }
        q.reset()

        #expect(q.used == 0)
        #expect(q.remaining == UsageQuota.allowance)
    }
}
