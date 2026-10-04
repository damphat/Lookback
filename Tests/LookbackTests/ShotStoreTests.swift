import XCTest
@testable import Lookback

/// Regression tests for timeline shot selection.
/// Guards the "nearest within tolerance, else empty state" contract
/// that the slider/activity strip depend on.
final class ShotStoreTests: XCTestCase {

    private func shot(at interval: TimeInterval) -> ShotStore.Shot {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(ShotStore.fmt.string(from: Date(timeIntervalSince1970: interval)) + ".jpg")
        return ShotStore.Shot(url: url, date: Date(timeIntervalSince1970: interval))
    }

    func testFilenameRoundtrip() {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        let name = ShotStore.fmt.string(from: d)
        XCTAssertEqual(ShotStore.fmt.date(from: name), d)
    }

    func testNearestWithinToleranceWins() {
        let shots = [shot(at: 1000), shot(at: 2000), shot(at: 3000)]
        let found = ShotStore.nearest(to: Date(timeIntervalSince1970: 2050), in: shots)
        XCTAssertEqual(found?.date, Date(timeIntervalSince1970: 2000))
    }

    func testOutsideToleranceReturnsNil() {
        // Slider must show "Máy nghỉ" instead of a far-away shot.
        let shots = [shot(at: 1000)]
        XCTAssertNil(ShotStore.nearest(to: Date(timeIntervalSince1970: 5000), in: shots))
    }

    func testEmptyListReturnsNil() {
        XCTAssertNil(ShotStore.nearest(to: Date(), in: []))
    }
}
