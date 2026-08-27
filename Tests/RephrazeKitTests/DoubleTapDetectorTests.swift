import Testing
import Foundation
@testable import RephrazeKit

@Suite("DoubleTapDetector")
struct DoubleTapDetectorTests {

    @Test("One tap is not a double tap")
    func singleTapDoesNotFire() {
        var detector = DoubleTapDetector(window: 0.4)
        #expect(detector.registerTap(at: 0.0) == false)
    }

    @Test("Two taps inside the window fire")
    func twoQuickTapsFire() {
        var detector = DoubleTapDetector(window: 0.4)
        #expect(detector.registerTap(at: 0.0) == false)
        #expect(detector.registerTap(at: 0.2) == true)
    }

    @Test("Two taps exactly on the boundary fire")
    func boundaryIsInclusive() {
        var detector = DoubleTapDetector(window: 0.4)
        _ = detector.registerTap(at: 0.0)
        #expect(detector.registerTap(at: 0.4) == true)
    }

    @Test("Two taps too far apart do not fire")
    func slowTapsDoNotFire() {
        var detector = DoubleTapDetector(window: 0.4)
        #expect(detector.registerTap(at: 0.0) == false)
        #expect(detector.registerTap(at: 0.9) == false)
    }

    /// A slow second tap becomes the *start* of a new pair rather than being
    /// discarded, so tap-pause-tap-tap still works.
    @Test("A late tap starts a fresh pair")
    func lateTapStartsNewPair() {
        var detector = DoubleTapDetector(window: 0.4)
        _ = detector.registerTap(at: 0.0)
        #expect(detector.registerTap(at: 0.9) == false)
        #expect(detector.registerTap(at: 1.0) == true)
    }

    /// Three fast taps must fire once, not twice -- otherwise a nervous
    /// triple-tap would trigger twice in a row.
    @Test("Three fast taps fire exactly once")
    func tripleTapFiresOnce() {
        var detector = DoubleTapDetector(window: 0.4)
        var fires = 0
        for t in [0.0, 0.15, 0.30] where detector.registerTap(at: t) { fires += 1 }
        #expect(fires == 1)
    }

    @Test("Four fast taps fire exactly twice")
    func quadTapFiresTwice() {
        var detector = DoubleTapDetector(window: 0.4)
        var fires = 0
        for t in [0.0, 0.15, 0.30, 0.45] where detector.registerTap(at: t) { fires += 1 }
        #expect(fires == 2)
    }

    @Test("reset() forgets a pending first tap")
    func resetForgetsPendingTap() {
        var detector = DoubleTapDetector(window: 0.4)
        _ = detector.registerTap(at: 0.0)
        detector.reset()
        #expect(detector.registerTap(at: 0.1) == false)
    }

    @Test("Default window matches the macOS double-click feel")
    func defaultWindowIsSane() {
        #expect(DoubleTapDetector.defaultWindow == 0.4)
    }
}
