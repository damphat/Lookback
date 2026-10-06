import XCTest
@testable import Lookback

/// Guards the live-pin mental model: selection near the trailing edge means
/// "watching now" and rides window changes; `tick` is the only writer of
/// from/to; the preset survives relaunch.
final class ScopePinTests: XCTestCase {
    func testAtEdgeIsLive() {
        let to = Date()
        XCTAssertTrue(TimeScope.isLive(to, to: to))
        XCTAssertTrue(TimeScope.isLive(to.addingTimeInterval(-30), to: to))
    }

    func testFarFromEdgeIsNotLive() {
        let to = Date()
        XCTAssertFalse(TimeScope.isLive(to.addingTimeInterval(-600), to: to))
        // Ahead of the edge also rides it (rescope pins it back to `to`).
        XCTAssertTrue(TimeScope.isLive(to.addingTimeInterval(600), to: to))
    }

    func testTickLivePresetRidesNow() {
        let s = TimeScope(defaults: .ephemeral())
        s.preset = .last1h
        s.tick(now: Date(), force: true)
        let firstTo = s.to
        s.tick(now: firstTo.addingTimeInterval(120))
        XCTAssertEqual(s.to.timeIntervalSince(firstTo), 120, accuracy: 1)
    }

    func testTickFixedPresetFrozenUnlessForced() {
        let s = TimeScope(defaults: .ephemeral())
        s.preset = .yesterdayAM
        s.tick(now: Date(), force: true)
        let (f, t) = (s.from, s.to)
        s.tick(now: Date().addingTimeInterval(3600))
        XCTAssertEqual(s.from, f)
        XCTAssertEqual(s.to, t)
    }

    func testPresetPersistsAcrossLaunches() {
        let d = UserDefaults.ephemeral()
        TimeScope(defaults: d).preset = .today
        XCTAssertEqual(TimeScope(defaults: d).preset, .today)
    }

    func testUnknownSavedPresetFallsBack() {
        let d = UserDefaults.ephemeral()
        d.set("không có preset này", forKey: "lookback.timePreset")
        XCTAssertEqual(TimeScope(defaults: d).preset, .last24h)
    }
}

private extension UserDefaults {
    static func ephemeral() -> UserDefaults {
        UserDefaults(suiteName: "lookback.tests.\(UUID().uuidString)")!
    }
}
