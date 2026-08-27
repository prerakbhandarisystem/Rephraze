import Testing
@testable import RephrazeKit

@Suite("SoloTapMonitor")
struct SoloTapMonitorTests {

    private func run(_ inputs: [SoloTapMonitor.Input]) -> [SoloTapMonitor.Output] {
        var monitor = SoloTapMonitor()
        return inputs.map { monitor.handle($0) }
    }

    private func fired(_ inputs: [SoloTapMonitor.Input]) -> Bool {
        run(inputs).contains(.soloTap)
    }

    private let down = SoloTapMonitor.Input.flags(target: true, others: false)
    private let up = SoloTapMonitor.Input.flags(target: false, others: false)

    // MARK: - Should fire

    @Test("Pressed and released alone is a solo tap")
    func soloTapFires() {
        #expect(fired([down, up]))
    }

    @Test("Three separate taps fire three times")
    func repeatedTapsFire() {
        var monitor = SoloTapMonitor()
        var count = 0
        for _ in 0..<3 {
            if monitor.handle(down) == .soloTap { count += 1 }
            if monitor.handle(up) == .soloTap { count += 1 }
        }
        #expect(count == 3)
    }

    @Test("Reported on release, not on press")
    func firesOnReleaseNotPress() {
        var monitor = SoloTapMonitor()
        #expect(monitor.handle(down) == .none)
        #expect(monitor.handle(up) == .soloTap)
    }

    // MARK: - Must NOT fire

    /// The big one: ⌘C must never look like a tap.
    @Test("Modifier plus a letter is ignored")
    func modifierPlusKeyIgnored() {
        #expect(!fired([down, .keyDown, up]))
    }

    @Test("Another modifier held first is ignored")
    func modifierBeforeIgnored() {
        #expect(!fired([.flags(target: true, others: true), up]))
    }

    @Test("Another modifier joining midway is ignored")
    func modifierDuringHoldIgnored() {
        #expect(!fired([down, .flags(target: true, others: true), up]))
    }

    @Test("A mouse click during the hold is ignored")
    func otherInputIgnored() {
        #expect(!fired([down, .otherInput, up]))
    }

    @Test("Typing with nothing held never fires")
    func typingAloneNeverFires() {
        #expect(!fired([.keyDown, .keyDown, .keyDown]))
    }

    @Test("Repeated presses without a release do not fire")
    func repeatedPressesDoNotFire() {
        #expect(!fired([down, down, down]))
    }

    // MARK: - Edge cases

    /// If the key was already held when the app launched we never saw the press,
    /// so the release must not be mistaken for a tap.
    @Test("A release with no matching press is ignored")
    func orphanReleaseIgnored() {
        #expect(!fired([up]))
    }

    @Test("Contamination does not leak into the next tap")
    func contaminationDoesNotLeak() {
        var monitor = SoloTapMonitor()
        _ = monitor.handle(down)
        _ = monitor.handle(.keyDown)
        #expect(monitor.handle(up) == .none)

        _ = monitor.handle(down)
        #expect(monitor.handle(up) == .soloTap)
    }

    /// macOS can switch our event tap off mid-hold, so we may miss the release.
    @Test("reset() drops an in-progress press")
    func resetDropsInProgressPress() {
        var monitor = SoloTapMonitor()
        _ = monitor.handle(down)
        monitor.reset()
        #expect(monitor.handle(up) == .none)
    }
}
