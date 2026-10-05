import XCTest
@testable import Lookback

/// Regression tests for timeline shot selection.
/// Guards the "nearest within tolerance, else empty state" contract
/// that the slider/activity strip depend on.
final class ShotStoreTests: XCTestCase {

    private func shot(at interval: TimeInterval, app: String? = nil, detail: String? = nil) -> ShotStore.Shot {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(
            ShotStore.filename(for: Date(timeIntervalSince1970: interval), app: app, detail: detail))
        return ShotStore.Shot(url: url, date: Date(timeIntervalSince1970: interval), app: app, detail: detail)
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

    // MARK: - 3-part filenames

    func testFilenameThreePartsRoundtrip() {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        let stem = ShotStore.filename(for: d, app: "Google Chrome", detail: "github.com")
            .replacingOccurrences(of: ".jpg", with: "")
        let p = ShotStore.parse(stem)
        XCTAssertEqual(p?.date, d)
        XCTAssertEqual(p?.app, "Google Chrome")
        XCTAssertEqual(p?.detail, "github.com")
    }

    func testFilenameAppOnlyRoundtrip() {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        let stem = ShotStore.filename(for: d, app: "Xcode", detail: nil)
            .replacingOccurrences(of: ".jpg", with: "")
        let p = ShotStore.parse(stem)
        XCTAssertEqual(p?.app, "Xcode")
        XCTAssertNil(p?.detail)
    }

    func testFilenameEmptyContextDegradesToTimestampOnly() {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            ShotStore.filename(for: d, app: nil, detail: "github.com"),
            ShotStore.fmt.string(from: d) + ".jpg")
        // Detail without app is dropped (part 3 needs part 2).
        let p = ShotStore.parse(ShotStore.fmt.string(from: d))
        XCTAssertEqual(p?.date, d)
        XCTAssertNil(p?.app)
    }

    func testSanitizeStripsSeparator() {
        XCTAssertEqual(ShotStore.sanitize("a__b/c:d"), "a_b-c-d")
    }

    // MARK: - Stats grouping

    func testStatsSortsAppsByCountDesc() {
        let now = Date().timeIntervalSince1970
        let shots = [shot(at: now, app: "Chrome", detail: "a.com"),
                     shot(at: now + 60, app: "Xcode"),
                     shot(at: now + 120, app: "Chrome", detail: "b.com"),
                     shot(at: now + 180, app: "Chrome", detail: "a.com")]
        let rows = AppStats.rows(for: shots)
        XCTAssertEqual(rows.map(\.app), ["Chrome", "Xcode"])
        XCTAssertEqual(rows[0].details.map { $0.0 }, ["a.com", "b.com"])
        XCTAssertEqual(rows[0].details.map { $0.1 }, [2, 1])
        XCTAssertTrue(rows[1].details.isEmpty)
    }

    func testStatsIgnoresOtherDays() {
        let yesterday = Date().addingTimeInterval(-86400)
        let shots = [shot(at: yesterday.timeIntervalSince1970, app: "Old")]
        XCTAssertTrue(AppStats.rows(for: shots).isEmpty)
    }
}
