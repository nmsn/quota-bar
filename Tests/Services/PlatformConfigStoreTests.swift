import XCTest
@testable import QuotaBar

final class PlatformConfigStoreTests: XCTestCase {

    // 隔离的 UserDefaults suite, 避免测试 fixture 污染真实用户配置 (.standard).
    // 之前用 .standard 导致 setAPIKey("sk-minimax") 覆盖了用户的真实 MiniMax token.
    private let testDefaults = UserDefaults(suiteName: "platform-config-store-tests")!

    override func tearDown() {
        super.tearDown()
        testDefaults.dictionaryRepresentation().keys.forEach { testDefaults.removeObject(forKey: $0) }
    }

    func testNewStoreIsNotConfigured() {
        let store = PlatformConfigStore(platformType: .glm_cn, userDefaults: testDefaults)
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(store.apiKey)
    }

    func testSetAPIKey() {
        let store = PlatformConfigStore(platformType: .glm_cn, userDefaults: testDefaults)
        store.setAPIKey("sk-test123")
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.apiKey, "sk-test123")
    }

    func testResetAPIKey() {
        let store = PlatformConfigStore(platformType: .glm_cn, userDefaults: testDefaults)
        store.setAPIKey("sk-test123")
        store.resetAPIKey()
        XCTAssertFalse(store.isConfigured)
    }

    func testPersistence() {
        let store1 = PlatformConfigStore(platformType: .glm_cn, userDefaults: testDefaults)
        store1.setAPIKey("sk-persist-test")

        let store2 = PlatformConfigStore(platformType: .glm_cn, userDefaults: testDefaults)
        XCTAssertEqual(store2.apiKey, "sk-persist-test")
        XCTAssertTrue(store2.isConfigured)
    }

    func testToConfigData() {
        let store = PlatformConfigStore(platformType: .glm_cn, userDefaults: testDefaults)
        store.setAPIKey("sk-test")

        let configData = store.toConfigData()
        XCTAssertEqual(configData.platformType, .glm_cn)
        XCTAssertEqual(configData.apiKey, "sk-test")
        XCTAssertEqual(configData.authHeader, "Authorization")
        XCTAssertEqual(configData.authPrefix, "Bearer ")
    }

    func testDefaultValues() {
        let store = PlatformConfigStore(platformType: .minimax_cn, userDefaults: testDefaults)
        XCTAssertEqual(store.authHeader, "Authorization")
        XCTAssertEqual(store.authPrefix, "Bearer ")
    }

    func testWhitespaceOnlyKeyIsNotConfigured() {
        let store = PlatformConfigStore(platformType: .glm_cn, userDefaults: testDefaults)
        store.setAPIKey("   ")
        XCTAssertFalse(store.isConfigured)
    }

    func testDifferentPlatformsAreIndependent() {
        let glm = PlatformConfigStore(platformType: .glm_cn, userDefaults: testDefaults)
        glm.setAPIKey("sk-glm")

        let minimax = PlatformConfigStore(platformType: .minimax_cn, userDefaults: testDefaults)
        minimax.setAPIKey("sk-minimax")

        XCTAssertEqual(glm.apiKey, "sk-glm")
        XCTAssertEqual(minimax.apiKey, "sk-minimax")
    }
}
