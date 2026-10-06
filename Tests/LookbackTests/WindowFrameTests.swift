import XCTest
@testable import Lookback

/// Guards the window-frame memory: remembered size wins, garbage or
/// off-screen origins fall back to a centered default.
final class WindowFrameTests: XCTestCase {
    private let min = CGSize(width: 900, height: 580)
    private let def = CGSize(width: 1160, height: 720)
    private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1079)

    private func restored(_ saved: CGRect?) -> CGRect {
        WindowFrame.restored(saved: saved, minSize: min, defaultSize: def, visible: visible)
    }

    func testNoSavedUsesCenteredDefault() {
        let r = restored(nil)
        XCTAssertEqual(r.size, def)
        XCTAssertEqual(r.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(r.midY, visible.midY, accuracy: 1)
    }

    func testSavedSizeAndOriginKept() {
        let saved = CGRect(x: 100, y: 100, width: 1300, height: 800)
        XCTAssertEqual(restored(saved), saved)
    }

    func testTooSmallSavedFallsBackToDefault() {
        let r = restored(CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertEqual(r.size, def)
    }

    func testOffscreenOriginRecenteredKeepingSize() {
        let r = restored(CGRect(x: 5000, y: 5000, width: 1300, height: 800))
        XCTAssertEqual(r.size, CGSize(width: 1300, height: 800))
        XCTAssertEqual(r.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(r.midY, visible.midY, accuracy: 1)
    }
}
