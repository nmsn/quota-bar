# Launch at Login + Keychain API Key Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a right-click “Launch at Login” toggle via `SMAppService`, and store platform API keys in the macOS Keychain with one-time migration from UserDefaults that clears plaintext keys after successful write.

**Architecture:** Introduce `KeychainStore` (`KeychainStoring`) and `LaunchAtLoginService` (`LaunchAtLoginServing`). `PlatformConfigStore` keeps non-secret fields in UserDefaults and routes `apiKey` through the keychain, migrating leftover plist keys on load. `StatusBarController` adds a checkable menu item bound to `LaunchAtLoginService`.

**Tech Stack:** Swift 5.9, macOS 14+, Security (Keychain), ServiceManagement (`SMAppService`), AppKit menus, XCTest, XcodeGen

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-16-launch-at-login-keychain-design.md`
- Bundle ID / Keychain service: `com.quota.statusbar`
- Keychain account: `PlatformType.rawValue`
- Accessibility: `kSecAttrAccessibleAfterFirstUnlock`
- After successful Keychain write (save or migrate): UserDefaults `api_key` must be `""`
- Never clear plaintext until Keychain write succeeds
- Launch-at-login default: off; system `SMAppService` status is source of truth (no UserDefaults flag)
- Menu copy: EN `Launch at Login` / ZH `开机时启动`
- Repo HITL: do not `git commit` / `git push` / open PR unless the user explicitly authorizes
- Build/test: `xcodegen generate` then `xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -destination 'platform=macOS' test`

---

## File Structure

```
Services/
  KeychainStore.swift              # Create: KeychainStoring + KeychainStore + InMemoryKeychainStore (test helper can live in Tests)
  LaunchAtLoginService.swift       # Create: LaunchAtLoginServing + LaunchAtLoginService
  Platforms/
    PlatformConfigStore.swift      # Modify: inject keychain; migrate; never persist plaintext api_key
StatusBar/
  StatusBarController.swift        # Modify: launch-at-login menu item + toggle handler
Resources/
  en.json                          # Modify: menu.launchAtLogin (+ failed)
  zh-Hans.json                     # Modify: same
Tests/
  Services/
    KeychainStoreTests.swift       # Create
    PlatformConfigStoreTests.swift # Modify: inject InMemoryKeychainStore; add migration tests
    LaunchAtLoginServiceTests.swift # Create (protocol/mock-focused)
```

---

### Task 1: KeychainStore

**Files:**
- Create: `Services/KeychainStore.swift`
- Create: `Tests/Services/KeychainStoreTests.swift`
- Create: `Tests/Mocks/InMemoryKeychainStore.swift`

**Interfaces:**
- Consumes: Security framework
- Produces:
  - `protocol KeychainStoring { func get(account: String) throws -> String?; func set(_ value: String, account: String) throws; func delete(account: String) throws }`
  - `final class KeychainStore: KeychainStoring` with `init(service: String = "com.quota.statusbar")`
  - `final class InMemoryKeychainStore: KeychainStoring` for tests

- [ ] **Step 1: Write failing tests**

Create `Tests/Mocks/InMemoryKeychainStore.swift`:

```swift
import Foundation
@testable import QuotaBar

final class InMemoryKeychainStore: KeychainStoring {
    private var storage: [String: String] = [:]
    var setError: Error?
    var getError: Error?
    var deleteError: Error?

    func get(account: String) throws -> String? {
        if let getError { throw getError }
        return storage[account]
    }

    func set(_ value: String, account: String) throws {
        if let setError { throw setError }
        storage[account] = value
    }

    func delete(account: String) throws {
        if let deleteError { throw deleteError }
        storage.removeValue(forKey: account)
    }
}
```

Create `Tests/Services/KeychainStoreTests.swift` (use a dedicated service name and clean up in tearDown so tests do not touch production items):

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodegen generate
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -destination 'platform=macOS' \
  -only-testing:'quota-bar-tests/KeychainStoreTests' test
```

Expected: FAIL — `KeychainStoring` / `KeychainStore` not found.

- [ ] **Step 3: Implement KeychainStore**

Create `Services/KeychainStore.swift`:

```swift
import Foundation
import Security

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

protocol KeychainStoring {
    func get(account: String) throws -> String?
    func set(_ value: String, account: String) throws
    func delete(account: String) throws
}

final class KeychainStore: KeychainStoring {
    private let service: String

    init(service: String = "com.quota.statusbar") {
        self.service = service
    }

    func get(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }
}
```

If XcodeGen does not auto-pick up new files under `Services/` / `Tests/`, re-run `xcodegen generate` (sources are directory-based).

- [ ] **Step 4: Run tests to verify they pass**

Same `xcodebuild` command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit (only if user authorizes)**

```bash
git add Services/KeychainStore.swift Tests/Services/KeychainStoreTests.swift Tests/Mocks/InMemoryKeychainStore.swift
git commit -m "$(cat <<'EOF'
feat: add KeychainStore for API key persistence

EOF
)"
```

---

### Task 2: PlatformConfigStore Keychain + migration

**Files:**
- Modify: `Services/Platforms/PlatformConfigStore.swift`
- Modify: `Tests/Services/PlatformConfigStoreTests.swift`

**Interfaces:**
- Consumes: `KeychainStoring` from Task 1; `InMemoryKeychainStore`
- Produces: `PlatformConfigStore.init(platformType:keychain:)` ; plaintext `api_key` never retained in UserDefaults after successful set/migrate

- [ ] **Step 1: Rewrite / extend failing tests**

Replace `Tests/Services/PlatformConfigStoreTests.swift` with (keep coverage, add migration + plaintext clearing):

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -destination 'platform=macOS' \
  -only-testing:'quota-bar-tests/PlatformConfigStoreTests' test
```

Expected: FAIL — `init(platformType:keychain:)` missing and/or plaintext still stored.

- [ ] **Step 3: Implement PlatformConfigStore changes**

Update `Services/Platforms/PlatformConfigStore.swift`:

1. Add `private let keychain: KeychainStoring`.
2. Change init to:

```swift
init(platformType: PlatformType, keychain: KeychainStoring = KeychainStore()) {
    self.platformType = platformType
    self.keychain = keychain
    self.defaultsKey = "quotabar.platform.\(platformType.rawValue)"
    // existing default field assignments...
    load()
    fillDefaultsFromTemplateIfNeeded()
}
```

3. In `load()`, after reading the dictionary fields, resolve API key:

```swift
private func load() {
    // ... existing UserDefaults dict load for non-secret fields ...
    // Do NOT assign apiKey from dict as the final source.
    let plaintext = (dict["api_key"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let plaintextOrNil = (plaintext?.isEmpty == false) ? plaintext : nil

    if let keychainKey = try? keychain.get(account: platformType.rawValue),
       !keychainKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        apiKey = keychainKey
        if plaintextOrNil != nil {
            clearPlaintextAPIKeyInDefaults()
        }
        return
    }

    if let plaintextOrNil {
        do {
            try keychain.set(plaintextOrNil, account: platformType.rawValue)
            apiKey = plaintextOrNil
            clearPlaintextAPIKeyInDefaults()
        } catch {
            // Keep plaintext in defaults; still expose for this session
            apiKey = plaintextOrNil
        }
        return
    }

    apiKey = nil
}
```

Note: `load()` currently early-returns when no defaults object exists — in that case still try Keychain-only:

```swift
guard let anyValue = UserDefaults.standard.object(forKey: defaultsKey) else {
    if let keychainKey = try? keychain.get(account: platformType.rawValue),
       !keychainKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        apiKey = keychainKey
    }
    return
}
```

4. Update `save()` so `"api_key"` is always `""`.

5. Add:

```swift
private func clearPlaintextAPIKeyInDefaults() {
    guard var dict = UserDefaults.standard.dictionary(forKey: defaultsKey) else { return }
    dict["api_key"] = ""
    UserDefaults.standard.set(dict, forKey: defaultsKey)
}
```

6. Update `setAPIKey`:

```swift
func setAPIKey(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        resetAPIKey()
        return
    }
    do {
        try keychain.set(trimmed, account: platformType.rawValue)
        apiKey = trimmed
        // Persist non-secret fields with empty api_key
        save()
        clearPlaintextAPIKeyInDefaults()
    } catch {
        // Do not claim success; leave previous apiKey unchanged
    }
}
```

7. Update `resetAPIKey`:

```swift
func resetAPIKey() {
    try? keychain.delete(account: platformType.rawValue)
    apiKey = nil
    save()
    clearPlaintextAPIKeyInDefaults()
}
```

Keep `fillDefaultsFromTemplateIfNeeded()` as-is (it calls `save()`, which now writes empty `api_key`).

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -destination 'platform=macOS' \
  -only-testing:'quota-bar-tests/PlatformConfigStoreTests' test
```

Expected: PASS. Also run full suite to catch regressions:

```bash
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -destination 'platform=macOS' test
```

- [ ] **Step 5: Commit (only if user authorizes)**

```bash
git add Services/Platforms/PlatformConfigStore.swift Tests/Services/PlatformConfigStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: store API keys in Keychain and migrate from UserDefaults

EOF
)"
```

---

### Task 3: LaunchAtLoginService

**Files:**
- Create: `Services/LaunchAtLoginService.swift`
- Create: `Tests/Services/LaunchAtLoginServiceTests.swift`
- Create: `Tests/Mocks/MockLaunchAtLoginService.swift`

**Interfaces:**
- Consumes: ServiceManagement (`SMAppService`)
- Produces:
  - `protocol LaunchAtLoginServing { var isEnabled: Bool { get }; func setEnabled(_ enabled: Bool) throws }`
  - `final class LaunchAtLoginService: LaunchAtLoginServing`
  - `enum LaunchAtLoginError: Error` (wrap underlying failures if useful)

- [ ] **Step 1: Write failing tests for mock / protocol usage**

`Tests/Mocks/MockLaunchAtLoginService.swift`:

```swift
import Foundation
@testable import QuotaBar

final class MockLaunchAtLoginService: LaunchAtLoginServing {
    var isEnabled: Bool = false
    var setEnabledError: Error?
    private(set) var lastSetEnabledValue: Bool?

    func setEnabled(_ enabled: Bool) throws {
        if let setEnabledError { throw setEnabledError }
        lastSetEnabledValue = enabled
        isEnabled = enabled
    }
}
```

`Tests/Services/LaunchAtLoginServiceTests.swift`:

```swift
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
```

(Real `SMAppService` register/unregister is verified manually on a `/Applications` build; unit tests stay mock-based.)

- [ ] **Step 2: Run tests — expect fail on missing types**

```bash
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -destination 'platform=macOS' \
  -only-testing:'quota-bar-tests/LaunchAtLoginServiceTests' test
```

Expected: FAIL — `LaunchAtLoginServing` not found.

- [ ] **Step 3: Implement LaunchAtLoginService**

Create `Services/LaunchAtLoginService.swift`:

```swift
import Foundation
import ServiceManagement

protocol LaunchAtLoginServing {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginError: Error {
    case registrationFailed(Error)
    case unregistrationFailed(Error)
}

final class LaunchAtLoginService: LaunchAtLoginServing {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                throw LaunchAtLoginError.registrationFailed(error)
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                throw LaunchAtLoginError.unregistrationFailed(error)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit (only if user authorizes)**

```bash
git add Services/LaunchAtLoginService.swift Tests/Services/LaunchAtLoginServiceTests.swift Tests/Mocks/MockLaunchAtLoginService.swift
git commit -m "$(cat <<'EOF'
feat: add LaunchAtLoginService wrapping SMAppService

EOF
)"
```

---

### Task 4: Right-click menu + i18n

**Files:**
- Modify: `StatusBar/StatusBarController.swift`
- Modify: `Resources/en.json`
- Modify: `Resources/zh-Hans.json`

**Interfaces:**
- Consumes: `LaunchAtLoginServing` / `LaunchAtLoginService.shared` or a stored property defaulting to `LaunchAtLoginService()`
- Produces: checkable menu item `menu.launchAtLogin`; toggle calls `setEnabled`; failures show `NSAlert` with `menu.launchAtLogin.failed`

- [ ] **Step 1: Add i18n strings**

In `Resources/en.json` add:

```json
"menu.launchAtLogin": "Launch at Login",
"menu.launchAtLogin.failed": "Could not update login item. Keep QuotaBar in the Applications folder and check System Settings → General → Login Items."
```

In `Resources/zh-Hans.json` add:

```json
"menu.launchAtLogin": "开机时启动",
"menu.launchAtLogin.failed": "无法更新登录项。请将 QuotaBar 放在「应用程序」文件夹，并在 系统设置 → 通用 → 登录项 中检查权限。"
```

- [ ] **Step 2: Wire menu in StatusBarController**

In `StatusBarController`:

1. Add property:

```swift
private let launchAtLoginService: LaunchAtLoginServing = LaunchAtLoginService()
```

(If testing the controller later, inject via init; not required for this task.)

2. In `showDisplaySettingsSubmenu()`, after `refreshItem` (or next to display/refresh — same level as those items), add:

```swift
let launchAtLoginItem = NSMenuItem(
    title: I18nService.shared.translate("menu.launchAtLogin"),
    action: #selector(toggleLaunchAtLogin(_:)),
    keyEquivalent: ""
)
launchAtLoginItem.target = self
launchAtLoginItem.state = launchAtLoginService.isEnabled ? .on : .off
```

Insert into `rootMenu` after `refreshItem` (before `platformItem`):

```swift
rootMenu.addItem(displaySettingsItem)
rootMenu.addItem(refreshItem)
rootMenu.addItem(launchAtLoginItem)
rootMenu.addItem(platformItem)
```

3. Add action:

```swift
@objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
    let enable = sender.state != .on
    do {
        try launchAtLoginService.setEnabled(enable)
    } catch {
        let alert = NSAlert()
        alert.messageText = I18nService.shared.translate("menu.launchAtLogin")
        alert.informativeText = I18nService.shared.translate("menu.launchAtLogin.failed")
        alert.alertStyle = .warning
        alert.addButton(withTitle: I18nService.shared.translate("menu.about.ok"))
        alert.runModal()
    }
    // Re-show or update state next open; clear menu so next right-click rebuilds from system status
    statusItem.menu = nil
}
```

Follow existing pattern for how the controller dismisses the menu after actions (if other toggles set `statusItem.menu = nil`, match that).

- [ ] **Step 3: Build to verify compile**

```bash
xcodegen generate
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual check (on machine)**

1. Run app from `/Applications` (or copy Debug build there).
2. Right-click → confirm「开机时启动」exists, default unchecked.
3. Enable → System Settings → General → Login Items lists QuotaBar.
4. Disable → removed from login items.
5. With a configured platform: confirm plist `api_key` is `""` and app still configured after quit/relaunch.

- [ ] **Step 5: Commit (only if user authorizes)**

```bash
git add StatusBar/StatusBarController.swift Resources/en.json Resources/zh-Hans.json
git commit -m "$(cat <<'EOF'
feat: add Launch at Login toggle to status bar menu

EOF
)"
```

---

### Task 5: Full verification

**Files:** none new

- [ ] **Step 1: Run full test suite**

```bash
xcodegen generate
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -destination 'platform=macOS' test
```

Expected: all tests PASS.

- [ ] **Step 2: Spec acceptance spot-check**

| Spec criterion | How to verify |
|----------------|---------------|
| Menu toggle matches system login item | Manual Task 4 Step 4 |
| plist `api_key` empty after configure | `defaults read com.quota.statusbar` / plutil |
| Legacy migrate + clear | Unit test `testMigrateFromUserDefaultsThenClearPlaintext` |
| Survive reboot | Manual: configure key, reboot, open app, still configured |
| Unit tests cover migrate/clear | Task 2 tests |

- [ ] **Step 3: Summarize for user; ask before commit/push/PR**

Do not push or open PR unless explicitly asked. Prefer feature branch off `main` (already used for the design doc branch, or create `feat/launch-at-login-keychain`).

---

## Self-Review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Right-click Launch at Login | Task 4 |
| `SMAppService`, system status as truth | Task 3–4 |
| Keychain fields (service/account/accessible) | Task 1 |
| PlatformConfigStore Keychain + migrate + clear plaintext | Task 2 |
| Keep plaintext if migrate fails | Task 2 `testMigrationKeepsPlaintextIfKeychainSetFails` |
| i18n EN/ZH | Task 4 |
| No Keychain Access UI / no always-prompt ACL | Task 1 accessible attr only |
| Tests for keychain, migration, launch mock | Tasks 1–3 |
| Full suite + acceptance | Task 5 |

No TBD/placeholder steps remain. Signatures are consistent across tasks (`KeychainStoring`, `LaunchAtLoginServing`, `PlatformConfigStore(platformType:keychain:)`).
