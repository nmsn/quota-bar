import XCTest
@testable import QuotaBar

final class LaunchAtLoginServiceTests: XCTestCase {
    func testMockToggleUpdatesState() throws {
        let mock = MockLaunchAtLoginService()
        XCTAssertFalse(mock.isEnabled)
        try mock.setEnabled(true)
        XCTAssertTrue(mock.isEnabled)
        XCTAssertEqual(mock.lastSetEnabledValue, true)
        try mock.setEnabled(false)
        XCTAssertFalse(mock.isEnabled)
    }

    func testMockPropagatesError() {
        struct Boom: Error {}
        let mock = MockLaunchAtLoginService()
        mock.setEnabledError = Boom()
        XCTAssertThrowsError(try mock.setEnabled(true))
        XCTAssertFalse(mock.isEnabled)
    }
}
