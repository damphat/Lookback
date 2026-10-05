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

    // MARK: - Time-domain summary

    private func summaryState(_ shots: [ShotStore.Shot], from: Date, to: Date) -> ActivityState {
        ActivityState(samples: shots, from: from, to: to)
    }

    func testSummarySortsAppsByMinutesDesc() {
        let now = Date()
        let shots = [shot(at: now.timeIntervalSince1970, app: "Chrome", detail: "a.com"),
                     shot(at: now.timeIntervalSince1970 + 60, app: "Xcode"),
                     shot(at: now.timeIntervalSince1970 + 120, app: "Chrome", detail: "b.com"),
                     shot(at: now.timeIntervalSince1970 + 180, app: "Chrome", detail: "a.com")]
        let rows = summaryState(shots, from: now.addingTimeInterval(-300),
                                to: now.addingTimeInterval(600)).summary()
        XCTAssertEqual(rows.map(\.app), ["Chrome", "Xcode"])
        XCTAssertEqual(rows[0].details.map { $0.0 }, ["a.com", "b.com"])
        XCTAssertGreaterThan(rows[0].details[0].1, rows[0].details[1].1)
        XCTAssertTrue(rows[1].details.isEmpty)
        // Stats agree with the bar: app minutes sum to region minutes.
        let st = summaryState(shots, from: now.addingTimeInterval(-300), to: now.addingTimeInterval(600))
        let regionMinutes = st.regions().filter { !$0.isSleep }.reduce(0) { $0 + $1.minutes }
        XCTAssertEqual(rows.reduce(0) { $0 + $1.minutes }, regionMinutes)
    }

    func testSummaryScopesToWindow() {
        let now = Date()
        let old = [shot(at: now.addingTimeInterval(-86400).timeIntervalSince1970, app: "Old")]
        let startOfToday = Calendar.current.startOfDay(for: now)
        XCTAssertTrue(summaryState(old, from: startOfToday, to: now).summary().isEmpty)
    }
}
