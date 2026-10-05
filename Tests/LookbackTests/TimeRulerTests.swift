import SwiftUI
import XCTest
@testable import Lookback

final class TimeRulerTests: XCTestCase {
    private var base: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func testTicksStayInsideWindowAndOrdered() {
        let to = base.addingTimeInterval(6 * 3600)
        let ticks = TimeRulerModel.ticks(from: base, to: to, width: 600)
        XCTAssertFalse(ticks.isEmpty)
        XCTAssertTrue(ticks.allSatisfy { $0.fraction >= 0 && $0.fraction < 1 })
        XCTAssertEqual(ticks.map(\.fraction), ticks.map(\.fraction).sorted())
    }

    func testTicksRespectMinSpacing() {
        // 24h across 600px: hourly ticks (25px apart) must give way to 3h+.
        let to = base.addingTimeInterval(24 * 3600)
        let ticks = TimeRulerModel.ticks(from: base, to: to, width: 600, minSpacing: 56)
        for i in 1..<ticks.count {
            XCTAssertGreaterThanOrEqual((ticks[i].fraction - ticks[i - 1].fraction) * 600, 56)
        }
    }

    func testNarrowWindowGetsMinuteTicks() {
        let to = base.addingTimeInterval(3600)
        let ticks = TimeRulerModel.ticks(from: base, to: to, width: 600)
        XCTAssertGreaterThanOrEqual(ticks.count, 3) // ≤15m steps
    }

    func testEdgeLabelNow() {
        XCTAssertEqual(TimeRulerModel.edgeLabel(to: Date(), now: Date()), "now")
        let old = base
        XCTAssertNotEqual(TimeRulerModel.edgeLabel(to: old, now: Date()), "now")
    }
}

final class AppPaletteTests: XCTestCase {
    private func rgb(_ name: String) -> (Double, Double, Double) {
        let c = NSColor(AppPalette.color(for: name)).usingColorSpace(.sRGB) ?? .clear
        func q(_ v: CGFloat) -> Double { (v * 1000).rounded() / 1000 }
        return (q(c.redComponent), q(c.greenComponent), q(c.blueComponent))
    }

    private func distinct(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Bool {
        a.0 != b.0 || a.1 != b.1 || a.2 != b.2
    }

    func testDailyAppsArePairwiseDistinct() {
        let apps = ["Chrome", "Code", "Xcode", "Slack", "Safari", "Terminal", "Finder"]
        let cols = apps.map { rgb($0) }
        for i in cols.indices {
            for j in (i + 1)..<cols.count {
                XCTAssertTrue(distinct(cols[i], cols[j]), "\(apps[i]) collides with \(apps[j])")
            }
        }
    }

    func testStableAcrossCalls() {
        let c = rgb("Some Random App 123")
        XCTAssertFalse(distinct(c, rgb("Some Random App 123")))
    }

    func testSiblingShadesAreDistinctByConstruction() {
        let sibs = (0..<4).map { rgbShade(app: "Code", index: $0) }
        for i in sibs.indices {
            for j in (i + 1)..<sibs.count {
                XCTAssertTrue(distinct(sibs[i], sibs[j]), "sibling shade \(i) collides with \(j)")
            }
        }
    }

    private func rgbShade(app: String, index: Int) -> (Double, Double, Double) {
        let c = NSColor(AppPalette.shade(app: app, index: index)).usingColorSpace(.sRGB) ?? .clear
        func q(_ v: CGFloat) -> Double { (v * 1000).rounded() / 1000 }
        return (q(c.redComponent), q(c.greenComponent), q(c.blueComponent))
    }
}

final class TimeTextTests: XCTestCase {
    func testShort() {
        XCTAssertEqual(TimeText.short(5), "5p")
        XCTAssertEqual(TimeText.short(57), "57p")
        XCTAssertEqual(TimeText.short(60), "1h")
        XCTAssertEqual(TimeText.short(185), "3h05p")
    }

    func testLong() {
        XCTAssertEqual(TimeText.long(57), "57 phút")
        XCTAssertEqual(TimeText.long(60), "1 giờ")
        XCTAssertEqual(TimeText.long(185), "3 giờ 5 phút")
    }

    func testAgo() {
        XCTAssertEqual(TimeText.ago(0), "hiện tại")
        XCTAssertEqual(TimeText.ago(5), "5 phút trước")
        XCTAssertEqual(TimeText.ago(185), "3h05p trước")
    }
}
