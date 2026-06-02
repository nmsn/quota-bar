import XCTest
@testable import QuotaBar

final class ConfigServiceTests: XCTestCase {
    func testDefaultActivePlatform() {
        let service = ConfigService.shared
        // Should have a valid active platform
        XCTAssertTrue(PlatformType.allCases.contains(service.activePlatform))
    }

    func testDefaultDisplayMode() {
        let service = ConfigService.shared
        XCTAssertNotNil(service.displayMode)
    }

    func testConfiguredPlatformsReturnsArray() {
        let service = ConfigService.shared
        let platforms = service.configuredPlatforms()
        XCTAssertNotNil(platforms)
    }

    func testStoreForPlatformReturnsSameInstance() {
        let service = ConfigService.shared
        let store1 = service.store(for: .deepseek)
        let store2 = service.store(for: .deepseek)
        XCTAssertTrue(store1 === store2)
    }

    func testStoreForDifferentPlatformsReturnsDifferentInstances() {
        let service = ConfigService.shared
        let store1 = service.store(for: .minimax_cn)
        let store2 = service.store(for: .deepseek)
        XCTAssertFalse(store1 === store2)
    }
}
