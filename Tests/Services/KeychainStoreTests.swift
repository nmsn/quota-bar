import XCTest
@testable import QuotaBar

final class KeychainStoreTests: XCTestCase {
    private let service = "com.quota.statusbar.tests.keychain"
    private let account = "test_account"
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: service)
        try? store.delete(account: account)
    }

    override func tearDown() {
        try? store.delete(account: account)
        store = nil
        super.tearDown()
    }

    func testSetAndGet() throws {
        try store.set("sk-secret", account: account)
        XCTAssertEqual(try store.get(account: account), "sk-secret")
    }

    func testUpdateOverwrites() throws {
        try store.set("old", account: account)
        try store.set("new", account: account)
        XCTAssertEqual(try store.get(account: account), "new")
    }

    func testDeleteRemovesValue() throws {
        try store.set("sk-secret", account: account)
        try store.delete(account: account)
        XCTAssertNil(try store.get(account: account))
    }

    func testGetMissingReturnsNil() throws {
        XCTAssertNil(try store.get(account: "missing_\(UUID().uuidString)"))
    }
}
