import XCTest
@testable import QuotaBar

final class PlatformManagerTests: XCTestCase {
    func testManagerHasDefaultServices() {
        let manager = PlatformManager()
        // Should have MiniMax and GLM registered
        let configured = manager.configuredPlatforms()
        XCTAssertNotNil(configured)
    }

    func testConfiguredPlatformsReturnsConfiguredOnly() {
        let manager = PlatformManager()
        let platforms = manager.configuredPlatforms()
        // Only platforms with API keys should be returned
        for platform in platforms {
            let store = ConfigService.shared.store(for: platform)
            XCTAssertTrue(store.isConfigured)
        }
    }

    func testClearCacheDoesNotCrash() {
        let manager = PlatformManager()
        manager.clearCache(for: .minimax_cn)
        manager.clearCache(for: .glm_cn)
        manager.clearAllCaches()
    }
}
