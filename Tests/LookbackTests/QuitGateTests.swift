import XCTest
@testable import Lookback

final class QuitGateTests: XCTestCase {
    func testCmdQDeniedByDefault() {
        XCTAssertFalse(QuitGate().shouldTerminate)
    }

    func testTrayQuitAllowed() {
        var g = QuitGate()
        g.allowQuit = true
        XCTAssertTrue(g.shouldTerminate)
    }

    func testSystemShutdownAllowed() {
        var g = QuitGate()
        g.systemShutdown = true
        XCTAssertTrue(g.shouldTerminate)
    }
}
