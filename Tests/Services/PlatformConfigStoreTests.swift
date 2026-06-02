import XCTest
@testable import QuotaBar

final class PlatformConfigStoreTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "quotabar.platform.deepseek")
        UserDefaults.standard.removeObject(forKey: "quotabar.platform.minimax")
    }

    func testNewStoreIsNotConfigured() {
        let store = PlatformConfigStore(platformType: .deepseek)
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(store.apiKey)
    }

    func testSetAPIKey() {
        let store = PlatformConfigStore(platformType: .deepseek)
        store.setAPIKey("sk-test123")
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.apiKey, "sk-test123")
    }

    func testResetAPIKey() {
        let store = PlatformConfigStore(platformType: .deepseek)
        store.setAPIKey("sk-test123")
        store.resetAPIKey()
        XCTAssertFalse(store.isConfigured)
    }

    func testPersistence() {
        let store1 = PlatformConfigStore(platformType: .deepseek)
        store1.setAPIKey("sk-persist-test")

        let store2 = PlatformConfigStore(platformType: .deepseek)
        XCTAssertEqual(store2.apiKey, "sk-persist-test")
        XCTAssertTrue(store2.isConfigured)
    }

    func testToConfigData() {
        let store = PlatformConfigStore(platformType: .deepseek)
        store.setAPIKey("sk-test")

        let configData = store.toConfigData()
        XCTAssertEqual(configData.platformType, .deepseek)
        XCTAssertEqual(configData.apiKey, "sk-test")
        XCTAssertEqual(configData.authHeader, "Authorization")
        XCTAssertEqual(configData.authPrefix, "Bearer ")
    }

    func testDefaultValues() {
        let store = PlatformConfigStore(platformType: .minimax_cn)
        XCTAssertEqual(store.authHeader, "Authorization")
        XCTAssertEqual(store.authPrefix, "Bearer ")
    }

    func testWhitespaceOnlyKeyIsNotConfigured() {
        let store = PlatformConfigStore(platformType: .deepseek)
        store.setAPIKey("   ")
        XCTAssertFalse(store.isConfigured)
    }

    func testDifferentPlatformsAreIndependent() {
        let deepseek = PlatformConfigStore(platformType: .deepseek)
        deepseek.setAPIKey("sk-deepseek")

        let minimax = PlatformConfigStore(platformType: .minimax_cn)
        minimax.setAPIKey("sk-minimax")

        XCTAssertEqual(deepseek.apiKey, "sk-deepseek")
        XCTAssertEqual(minimax.apiKey, "sk-minimax")
    }
}
