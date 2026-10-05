import XCTest
@testable import Lookback

/// Tapping a cell must show that cell's thumbnail: the tap fraction is the
/// cell centre, and the centre maps back to the same cell.
final class TimelineLayoutTests: XCTestCase {
    func testTapFractionRoundTripsToSameCell() {
        let cells = 48
        for i in 0..<cells {
            let f = TimelineLayout.fraction(forCell: i, cells: cells)
            XCTAssertEqual(TimelineLayout.cellIndex(forFraction: f, cells: cells), i, "cell \(i)")
        }
    }

    func testEdgeFractionsStayInBounds() {
        XCTAssertEqual(TimelineLayout.cellIndex(forFraction: 0, cells: 48), 0)
        XCTAssertEqual(TimelineLayout.cellIndex(forFraction: 1, cells: 48), 47)
    }
}
