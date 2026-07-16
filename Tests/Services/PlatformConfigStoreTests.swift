import XCTest
@testable import QuotaBar

final class PlatformConfigStoreTests: XCTestCase {
    private var keychain: InMemoryKeychainStore!
    private let deepseekKey = "quotabar.platform.deepseek"
    private let minimaxKey = "quotabar.platform.minimax_cn"

    override func setUp() {
        super.setUp()
        keychain = InMemoryKeychainStore()
        UserDefaults.standard.removeObject(forKey: deepseekKey)
        UserDefaults.standard.removeObject(forKey: minimaxKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: deepseekKey)
        UserDefaults.standard.removeObject(forKey: minimaxKey)
        keychain = nil
        super.tearDown()
    }

    private func makeStore(_ type: PlatformType) -> PlatformConfigStore {
        PlatformConfigStore(platformType: type, keychain: keychain)
    }

    func testNewStoreIsNotConfigured() {
        let store = makeStore(.deepseek)
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(store.apiKey)
    }

    func testSetAPIKeyWritesKeychainAndClearsDefaults() throws {
        let store = makeStore(.deepseek)
        store.setAPIKey("sk-test123")
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(store.apiKey, "sk-test123")
        XCTAssertEqual(try keychain.get(account: "deepseek"), "sk-test123")
        let dict = UserDefaults.standard.dictionary(forKey: deepseekKey)
        XCTAssertEqual(dict?["api_key"] as? String, "")
    }

    func testResetAPIKey() throws {
        let store = makeStore(.deepseek)
        store.setAPIKey("sk-test123")
        store.resetAPIKey()
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(try keychain.get(account: "deepseek"))
    }

    func testPersistenceViaKeychain() {
        let store1 = makeStore(.deepseek)
        store1.setAPIKey("sk-persist-test")
        let store2 = makeStore(.deepseek)
        XCTAssertEqual(store2.apiKey, "sk-persist-test")
        XCTAssertTrue(store2.isConfigured)
    }

    func testMigrateFromUserDefaultsThenClearPlaintext() throws {
        UserDefaults.standard.set([
            "api_base_url": "https://api.deepseek.com",
            "auth_header": "Authorization",
            "auth_prefix": "Bearer ",
            "region": "domestic",
            "api_key": "sk-legacy"
        ], forKey: deepseekKey)

        let store = makeStore(.deepseek)
        XCTAssertEqual(store.apiKey, "sk-legacy")
        XCTAssertEqual(try keychain.get(account: "deepseek"), "sk-legacy")
        let dict = UserDefaults.standard.dictionary(forKey: deepseekKey)
        XCTAssertEqual(dict?["api_key"] as? String, "")
    }

    func testMigrationKeepsPlaintextIfKeychainSetFails() throws {
        struct Boom: Error {}
        keychain.setError = Boom()
        UserDefaults.standard.set([
            "api_base_url": "https://api.deepseek.com",
            "auth_header": "Authorization",
            "auth_prefix": "Bearer ",
            "region": "domestic",
            "api_key": "sk-legacy"
        ], forKey: deepseekKey)

        let store = makeStore(.deepseek)
        // Still usable from memory / defaults path for this session intent:
        // Spec: keep plist if migrate write fails. Store should expose key from defaults fallback.
        XCTAssertEqual(store.apiKey, "sk-legacy")
        let dict = UserDefaults.standard.dictionary(forKey: deepseekKey)
        XCTAssertEqual(dict?["api_key"] as? String, "sk-legacy")
    }

    func testToConfigData() {
        let store = makeStore(.deepseek)
        store.setAPIKey("sk-test")
        let configData = store.toConfigData()
        XCTAssertEqual(configData.platformType, .deepseek)
        XCTAssertEqual(configData.apiKey, "sk-test")
        XCTAssertEqual(configData.authHeader, "Authorization")
        XCTAssertEqual(configData.authPrefix, "Bearer ")
    }

    func testDefaultValues() {
        let store = makeStore(.minimax_cn)
        XCTAssertEqual(store.authHeader, "Authorization")
        XCTAssertEqual(store.authPrefix, "Bearer ")
    }

    func testWhitespaceOnlyKeyIsNotConfigured() {
        let store = makeStore(.deepseek)
        store.setAPIKey("   ")
        XCTAssertFalse(store.isConfigured)
    }

    func testDifferentPlatformsAreIndependent() {
        let deepseek = makeStore(.deepseek)
        deepseek.setAPIKey("sk-deepseek")
        let minimax = makeStore(.minimax_cn)
        minimax.setAPIKey("sk-minimax")
        XCTAssertEqual(deepseek.apiKey, "sk-deepseek")
        XCTAssertEqual(minimax.apiKey, "sk-minimax")
    }
}
