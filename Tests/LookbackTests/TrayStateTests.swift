import XCTest
@testable import Lookback

/// Locks the tray state→UI mapping: the icon keeps one face (dimmed when
/// stopped), the tooltip names the state, the menu names the action.
/// Regression guard — a re-read of `paused` inside a `$paused` sink sees
/// the PREVIOUS value (@Published fires from willSet), which once left the
/// tray exactly one toggle behind, then inverted.
final class TrayStateTests: XCTestCase {
    func testRunningReadsRunning() {
        XCTAssertFalse(TrayState.dimmed(paused: false))
        XCTAssertEqual(TrayState.toolTip(paused: false), "Lookback")
        XCTAssertEqual(TrayState.menuTitle(paused: false), "Tạm dừng chụp")
    }

    func testPausedReadsPaused() {
        XCTAssertTrue(TrayState.dimmed(paused: true))
        XCTAssertEqual(TrayState.toolTip(paused: true), "Lookback (đang dừng chụp)")
        XCTAssertEqual(TrayState.menuTitle(paused: true), "Tiếp tục chụp")
    }

    func testIconFaceNeverChanges() {
        // One face for both states — dimming carries the state, so no
        // state/action glyph ambiguity is possible.
        XCTAssertEqual(TrayState.symbol, "clock.arrow.circlepath")
    }
}
