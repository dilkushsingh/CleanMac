import XCTest
@testable import CleanMac

final class UnlockGestureDetectorTests: XCTestCase {
    final class FakeClock {
        var now: ContinuousClock.Instant = ContinuousClock.now
        func advance(_ seconds: Double) {
            now = now.advanced(by: .milliseconds(Int(seconds * 1000)))
        }
    }

    func makeDetector(hold: Double = 3.0) -> (UnlockGestureDetector, FakeClock, () -> Int, () -> Double) {
        let clock = FakeClock()
        let d = UnlockGestureDetector(holdDuration: hold) { clock.now }
        var unlocks = 0
        var progress: Double = 0
        d.onUnlock = { unlocks += 1 }
        d.onProgress = { progress = $0 }
        return (d, clock, { unlocks }, { progress })
    }

    func testSpaceOnlyDoesNotUnlock() {
        let (d, c, unlocks, _) = makeDetector()
        d.space(down: true)
        c.advance(5); d.tick()
        XCTAssertEqual(unlocks(), 0)
    }

    func testTrackpadOnlyDoesNotUnlock() {
        let (d, c, unlocks, _) = makeDetector()
        d.trackpad(down: true)
        c.advance(5); d.tick()
        XCTAssertEqual(unlocks(), 0)
    }

    func testBothHeldFullDurationUnlocks() {
        let (d, c, unlocks, progress) = makeDetector(hold: 3.0)
        d.space(down: true); d.trackpad(down: true)
        c.advance(1.5); d.tick()
        XCTAssertEqual(progress(), 0.5, accuracy: 0.01)
        XCTAssertEqual(unlocks(), 0)
        c.advance(1.5); d.tick()
        XCTAssertEqual(unlocks(), 1)
    }

    func testReleaseResetsProgress() {
        let (d, c, unlocks, progress) = makeDetector(hold: 3.0)
        d.space(down: true); d.trackpad(down: true)
        c.advance(2); d.tick()
        XCTAssertGreaterThan(progress(), 0)
        d.space(down: false)
        XCTAssertEqual(progress(), 0)
        c.advance(5); d.tick()
        XCTAssertEqual(unlocks(), 0)
    }

    func testIdempotentDownEvents() {
        let (d, c, unlocks, _) = makeDetector(hold: 1.0)
        d.space(down: true); d.space(down: true); d.space(down: true)
        d.trackpad(down: true); d.trackpad(down: true)
        c.advance(1.1); d.tick()
        XCTAssertEqual(unlocks(), 1)
    }

    func testUnlockFiresOnce() {
        let (d, c, unlocks, _) = makeDetector(hold: 1.0)
        d.space(down: true); d.trackpad(down: true)
        c.advance(2); d.tick()
        c.advance(2); d.tick()
        XCTAssertEqual(unlocks(), 1)
    }

    func testResetClearsEverything() {
        let (d, c, unlocks, progress) = makeDetector(hold: 1.0)
        d.space(down: true); d.trackpad(down: true)
        c.advance(0.5); d.tick()
        d.reset()
        XCTAssertEqual(progress(), 0)
        c.advance(2); d.tick()
        XCTAssertEqual(unlocks(), 0)
    }
}

final class AppSettingsNormalizationTests: XCTestCase {
    func testAutoUnlockClamps() {
        // Current bounds: 60 s … 300 s, snapped to 30 s steps.
        XCTAssertEqual(AppSettings.normalizeAutoUnlock(0), 60)
        XCTAssertEqual(AppSettings.normalizeAutoUnlock(5), 60)
        XCTAssertEqual(AppSettings.normalizeAutoUnlock(59), 60)
        XCTAssertEqual(AppSettings.normalizeAutoUnlock(60), 60)
        XCTAssertEqual(AppSettings.normalizeAutoUnlock(120), 120)
        XCTAssertEqual(AppSettings.normalizeAutoUnlock(1200), 300)
    }

    func testHoldClamps() {
        XCTAssertEqual(AppSettings.normalizeHold(0), 2.0, accuracy: 0.001)
        XCTAssertEqual(AppSettings.normalizeHold(1.9), 2.0, accuracy: 0.001)
        XCTAssertEqual(AppSettings.normalizeHold(3.1), 3.0, accuracy: 0.001)
        XCTAssertEqual(AppSettings.normalizeHold(3.3), 3.5, accuracy: 0.001)
        XCTAssertEqual(AppSettings.normalizeHold(99), 5.0, accuracy: 0.001)
    }
}
