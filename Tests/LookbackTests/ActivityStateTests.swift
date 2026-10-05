import XCTest
@testable import Lookback

/// Cell-model invariants: regions tile [from, to] exactly, children tile
/// their parent, and `view(at:)` is the only displayed lookup.
final class ActivityStateTests: XCTestCase {
    private var base: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    private func state(_ samples: [(Double, String?, String?)] = [], span: Double = 3600) -> ActivityState {
        var st = ActivityState(from: base, to: base.addingTimeInterval(span))
        for (t, a, d) in samples { st.addSample(date: base.addingTimeInterval(t), app: a, detail: d) }
        return st
    }

    private func assertTiles(_ regs: [ActivityState.Region], from: Date, to: Date,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(regs.isEmpty, file: file, line: line)
        XCTAssertEqual(regs.first!.start, from, file: file, line: line)
        XCTAssertEqual(regs.last!.end, to, file: file, line: line)
        for i in 1..<regs.count {
            XCTAssertEqual(regs[i].start, regs[i - 1].end,
                "gap/overlap between region \(i - 1) and \(i)", file: file, line: line)
        }
    }

    func testDefaultViewIsLast24h() {
        let st = ActivityState()
        XCTAssertEqual(st.to.timeIntervalSince(st.from), 24 * 3600, accuracy: 5)
    }

    func testTwoLevelRegions() {
        let st = state([(0, "Chrome", "a.com"), (60, "Chrome", "a.com"), (120, "Chrome", "b.com")])
        let regs = st.regions().filter { !$0.isSleep }
        XCTAssertEqual(regs.count, 1)
        XCTAssertEqual(regs[0].count, 3)
        XCTAssertEqual(regs[0].children.map(\.detail), ["a.com", "b.com"])
        XCTAssertEqual(regs[0].children.map(\.count), [2, 1])
    }

    func testSleepRegionOnGap() {
        let st = state([(0, "Chrome", nil), (600, "Chrome", nil)])
        XCTAssertEqual(st.regions().filter(\.isSleep).count, 2)
    }

    func testRegionsTileWindowExactly() {
        // 120 → 900 is a 780s gap: the B run splits (mid sleep), plus the
        // trailing sleep after the last cell edge (900 + 150s).
        let st = state([(0, "A", nil), (60, "A", nil), (120, "B", "x"), (900, "B", "x")])
        let regs = st.regions()
        assertTiles(regs, from: base, to: base.addingTimeInterval(3600))
        XCTAssertEqual(regs.filter(\.isSleep).count, 2)
        XCTAssertEqual(regs.filter { !$0.isSleep }.map(\.count), [2, 1, 1])
    }

    func testChildrenTileParent() {
        var st = state(span: 3600)
        for i in 0..<10 {
            st.addSample(date: base.addingTimeInterval(Double(i * 60)),
                         app: "Code", detail: i < 5 ? "Lookback" : "Clock")
        }
        let regs = st.regions().filter { !$0.isSleep }
        XCTAssertEqual(regs.count, 1)
        let kids = regs[0].children
        XCTAssertEqual(kids.count, 2)
        XCTAssertEqual(kids[0].start, regs[0].start)
        XCTAssertEqual(kids[1].end, regs[0].end)
        XCTAssertEqual(kids[1].start, kids[0].end) // exact shared edge, no gap
    }

    func testNilDetailLeavesBaseColour() {
        let st = state([(0, "A", nil), (60, "A", "x.com"), (120, "A", nil)])
        let regs = st.regions().filter { !$0.isSleep }
        XCTAssertEqual(regs.count, 1)
        XCTAssertEqual(regs[0].children.map(\.detail), ["x.com"])
    }

    func testViewAtIsSingleTruth() {
        let st = state([(0, "Code", "Lookback"), (60, "Code", "Lookback"), (120, "Code", "Clock")])
        let regs = st.regions()
        for t in stride(from: 0.0, through: 300, by: 15) {
            let v = st.view(at: base.addingTimeInterval(t), in: regs)
            let inApp = regs.first { $0.start <= base.addingTimeInterval(t) && base.addingTimeInterval(t) <= $0.end }
                .map { !$0.isSleep } ?? false
            if inApp {
                guard case .app = v else {
                    return XCTFail("t=\(t): inside app region but verdict has no shot")
                }
            }
        }
    }

    func testViewAtTopChildren() {
        var st = state(span: 7200)
        for i in 0..<7 {
            st.addSample(date: base.addingTimeInterval(Double(i * 60)), app: "Chrome", detail: "d\(i)")
        }
        let regs = st.regions().filter { !$0.isSleep }
        XCTAssertEqual(regs.count, 1)
        XCTAssertEqual(regs[0].count, 7)
        XCTAssertEqual(regs[0].children.count, 7)
    }

    func testNearestSampleBinarySearchEdges() {
        // No tolerance: nearest within the given range, nil when empty.
        let st = state([(0, "A", nil), (120, "A", nil)])
        XCTAssertNil(st.nearestSample(to: base.addingTimeInterval(-100),
                                      from: base.addingTimeInterval(30),
                                      through: base.addingTimeInterval(60)))
        XCTAssertEqual(st.nearestSample(to: base.addingTimeInterval(-100),
                                        from: base, through: base.addingTimeInterval(60))?.date, base)
        XCTAssertEqual(st.nearestSample(to: base.addingTimeInterval(119),
                                        from: base, through: base.addingTimeInterval(200))?.date,
                       base.addingTimeInterval(120))
    }

    func testBulkInitSortsShots() {
        let shots = [60.0, 0.0, 120.0].map {
            ShotStore.Shot(url: URL(fileURLWithPath: "/tmp/x.jpg"), date: base.addingTimeInterval($0), app: "A", detail: nil)
        }
        let st = ActivityState(samples: shots, from: base, to: base.addingTimeInterval(3600))
        XCTAssertEqual(st.samples.map(\.date), st.samples.map(\.date).sorted())
    }

    func testDenseSyntheticTilesAndIsFast() {
        let st = ActivityState.synthetic(count: 1440)
        let t0 = Date()
        let regs = st.regions()
        _ = st.view(at: base.addingTimeInterval(12 * 3600), in: regs)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.0)
        assertTiles(regs, from: st.from, to: st.to)
    }

    func testChildColoursDistinct() {
        XCTAssertNotEqual(ActivityState.hue(for: "Lookback"), ActivityState.hue(for: "Clock"))
    }
}
