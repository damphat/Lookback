import XCTest
@testable import Lookback

/// Tests for the activity bar model: contiguous same-app segments,
/// stable colours, position math, and tick generation.
final class AppActivityBarTests: XCTestCase {

    private func shot(at t: TimeInterval, app: String?) -> ShotStore.Shot {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let d = base.addingTimeInterval(t)
        let url = URL(fileURLWithPath: "/tmp/\(t).jpg")
        return ShotStore.Shot(url: url, date: d, app: app, detail: nil)
    }

    private var window: (Date, Date) {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return (base, base.addingTimeInterval(3600))
    }

    func testContiguousSameAppMergesIntoOneSegment() {
        let (from, to) = window
        let shots = [shot(at: 0, app: "Chrome"),
                     shot(at: 60, app: "Chrome"),
                     shot(at: 120, app: "Chrome")]
        let segs = AppActivityBarModel.segments(shots: shots, from: from, to: to)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].app, "Chrome")
        XCTAssertEqual(segs[0].shots.count, 3)
    }

    func testAppChangeSplitsSegments() {
        let (from, to) = window
        let shots = [shot(at: 0, app: "Chrome"),
                     shot(at: 60, app: "Xcode"),
                     shot(at: 120, app: "Chrome")]
        let segs = AppActivityBarModel.segments(shots: shots, from: from, to: to)
        XCTAssertEqual(segs.map(\.app), ["Chrome", "Xcode", "Chrome"])
    }

    func testLongGapSplitsSameApp() {
        let (from, to) = window
        let shots = [shot(at: 0, app: "Chrome"),
                     shot(at: 600, app: "Chrome")] // 10 min > 5 min sessionGap
        let segs = AppActivityBarModel.segments(shots: shots, from: from, to: to)
        XCTAssertEqual(segs.count, 2)
    }

    func testUnknownAppGroupedTogether() {
        let (from, to) = window
        let shots = [shot(at: 0, app: nil), shot(at: 60, app: nil)]
        let segs = AppActivityBarModel.segments(shots: shots, from: from, to: to)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].app, AppStats.unknownApp)
    }

    func testColorIsStablePerApp() {
        XCTAssertEqual(AppActivityBarModel.hue(for: "Chrome"),
                       AppActivityBarModel.hue(for: "Chrome"))
        XCTAssertNotEqual(AppActivityBarModel.hue(for: "Chrome"),
                          AppActivityBarModel.hue(for: "Xcode"))
    }

    func testPositionRoundtrip() {
        let (from, to) = window
        let d = from.addingTimeInterval(1234)
        let px = AppActivityBarModel.x(d, from: from, to: to, width: 1000)
        let back = AppActivityBarModel.date(at: px, from: from, to: to, width: 1000)
        XCTAssertEqual(back.timeIntervalSince1970, d.timeIntervalSince1970,
                       accuracy: 0.01)
        XCTAssertEqual(AppActivityBarModel.x(from, from: from, to: to, width: 1000), 0)
        XCTAssertEqual(AppActivityBarModel.x(to, from: from, to: to, width: 1000), 1000)
    }

    func testIdlesFindsSleepGapAndTrailingEdge() {
        let (from, to) = window // [base, base+3600]
        let shots = [shot(at: 0, app: "Chrome"),
                     shot(at: 600, app: "Chrome")]
        let gaps = AppActivityBarModel.idles(shots: shots, from: from, to: to)
        XCTAssertEqual(gaps.count, 2)
        XCTAssertEqual(gaps[0].start, from.addingTimeInterval(0))
        XCTAssertEqual(gaps[0].end, from.addingTimeInterval(600))
        XCTAssertEqual(gaps[0].minutes, 10)
        XCTAssertEqual(gaps[1].start, from.addingTimeInterval(600))
        XCTAssertEqual(gaps[1].end, to)
    }

    func testNoIdleForDenseShots() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let shots = (0..<6).map { shot(at: Double($0 * 60), app: "Chrome") }
        let gaps = AppActivityBarModel.idles(
            shots: shots,
            from: base.addingTimeInterval(-60),
            to: base.addingTimeInterval(360))
        XCTAssertTrue(gaps.isEmpty)
    }

    func testWholeWindowIdleWhenNoShots() {
        let (from, to) = window
        let gaps = AppActivityBarModel.idles(shots: [], from: from, to: to)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps[0].minutes, 60)
    }

    func testTicksBoundedAndInsideWindow() {
        let (from, to) = window
        let ticks = AppActivityBarModel.ticks(from: from, to: to)
        XCTAssertFalse(ticks.isEmpty)
        XCTAssertLessThanOrEqual(ticks.count, 8)
        XCTAssertTrue(ticks.allSatisfy { $0 >= from && $0 <= to })
    }
}
