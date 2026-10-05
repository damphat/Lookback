import XCTest
@testable import Lookback

final class AutomationStatusTests: XCTestCase {
    func testGrantedMapsToNotDenied() {
        XCTAssertFalse(ActiveContext.automationDenied(status: noErr))
    }

    func testDeniedAndConsentRequiredMapToDenied() {
        XCTAssertTrue(ActiveContext.automationDenied(status: -1743)) // errAEEventNotPermitted
        XCTAssertTrue(ActiveContext.automationDenied(status: -1744)) // errAEEventWouldRequireUserConsent
    }
}
