# 开机自启 + API Key Keychain 持久化设计

**日期:** 2026-07-16  
**状态:** 已确认  
**方案:** 方案 2（SMAppService 自启 + Keychain 存 Key）

## 概述

为 QuotaBar 增加「开机自启」设置，并将各平台 API Key 从 `UserDefaults`（明文 plist）迁移到 macOS Keychain，迁移成功后清除原存储位置中的明文 Key，以解决重启后需重新填写 Key 的问题，并避免密钥长期留在偏好设置文件中。

## 背景与问题

- 当前缺少开机自启入口。
- API Key 存在 `UserDefaults`：`~/Library/Preferences/com.quota.statusbar.plist`，键为 `quotabar.platform.{platform}` 字典中的 `api_key`。
- 用户反馈：整机重启后需要重新填写 Key；退出再打开通常仍在。安装路径固定为 `/Applications`。
- 用户未精确区分「仅 Key 丢失」还是「全部设置丢失」，但交互上表现为要重新填 Key。

## 目标

1. 右键菜单提供可勾选的「开机时启动」，默认关闭。
2. API Key 存 Keychain；非敏感平台配置仍用 UserDefaults。
3. 从 UserDefaults 一次性迁移旧 Key；**迁移/保存成功后必须清除原位置明文**。
4. 保存/读取 Key 时不主动唤起「钥匙串访问」App，也不为拥有者 App 设置「每次访问都要授权」。
5. TDD：Keychain 与迁移逻辑可测；自启逻辑可 mock。

## 非目标

- 不改动 Popover 里输入 Key 的主流程外观（仍在现有配置区粘贴保存）。
- 不把非敏感配置（base URL、region 等）迁入 Keychain。
- 不实现跨设备 iCloud Keychain 同步（使用本机登录钥匙串即可）。
- 不在本设计中改代码签名策略（现有 ad-hoc）；若 `SMAppService.register` 在未签名包上失败，以用户可见错误提示为准。

## 架构

```
StatusBarController
  └─ LaunchAtLoginService          -- SMAppService.mainApp 查询/注册/注销
  └─ 右键菜单「开机时启动」勾选

PlatformConfigStore
  └─ UserDefaults                  -- api_base_url / region / auth_* 等
  └─ KeychainStore                 -- api_key（按平台 account）

ConfigService                      -- 不变，继续持有 PlatformConfigStore
```

| 单元 | 职责 | 依赖 |
|------|------|------|
| `LaunchAtLoginService` | `isEnabled`、`setEnabled(_:)`，封装 `SMAppService` | ServiceManagement |
| `KeychainStore` | 按 service/account 增删改查 Generic Password | Security |
| `PlatformConfigStore` | 非敏感配置 UserDefaults；Key 走 Keychain；迁移并清明文 | KeychainStore |
| `StatusBarController` | 菜单项与勾选状态 | LaunchAtLoginService、I18n |

## 开机自启

### UI

- 位置：右键菜单，与「显示设置 / 刷新间隔」同级。
- 类型：可勾选 `NSMenuItem`。
- i18n 键：
  - `menu.launchAtLogin` → EN: `Launch at Login` / ZH: `开机时启动`
  - `menu.launchAtLogin.failed` → 注册/注销失败时 alert 正文

### 行为

- 每次打开右键菜单时，用 `SMAppService.mainApp.status == .enabled` 刷新勾选（**不**另存 UserDefaults；系统状态为唯一真源）。
- 点击：未启用则 `register()`；已启用则 `unregister()`。
- 默认：未注册。
- `register` 失败：保持未勾选，`NSAlert` 简短说明（例如需将 App 放在「应用程序」文件夹，或检查系统「登录项」权限）。

### API 草图

```swift
protocol LaunchAtLoginServing {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

final class LaunchAtLoginService: LaunchAtLoginServing {
    // SMAppService.mainApp.status / register() / unregister()
}
```

## Keychain

### 条目字段

| 字段 | 值 |
|------|-----|
| class | `kSecClassGenericPassword` |
| service | `com.quota.statusbar`（与 `PRODUCT_BUNDLE_IDENTIFIER` 一致） |
| account | `PlatformType.rawValue`（如 `minimax_cn`、`deepseek`） |
| value data | API Key UTF-8 |
| accessible | `kSecAttrAccessibleAfterFirstUnlock` |

用户在 App 内保存 Key 时：静默 `SecItemAdd` / `SecItemUpdate`，不打开钥匙串访问 App。

### KeychainStore API 草图

```swift
protocol KeychainStoring {
    func get(account: String) throws -> String?
    func set(_ value: String, account: String) throws
    func delete(account: String) throws
}
```

测试可用注入实现或独立 `service` 前缀，避免污染真实登录钥匙串中的生产条目。

## PlatformConfigStore 变更

### 读写

- `load()`：从 UserDefaults 加载非敏感字段；Key 从 Keychain 读取。
- `setAPIKey(_:)`：写入 Keychain；然后 `clearPlaintextAPIKeyInDefaults()`。
- `resetAPIKey()`：删除 Keychain 条目；清除 UserDefaults 中 `api_key`。
- `save()`（非敏感）：UserDefaults 字典中 **`api_key` 固定写 `""`**，不再写入明文。

### 迁移与清除（硬性要求）

读取优先级：

1. Keychain 有非空 Key → 使用它；若 UserDefaults 仍有非空 `api_key`，清除 plist 明文（兜底）。
2. Keychain 无、UserDefaults 有非空 `api_key` → 写入 Keychain；**仅当 Keychain 写入成功后**清除 plist 明文；写入失败则保留 plist，避免两头皆空。
3. 两边皆无 → `apiKey == nil` / 未配置。

清除范围：

- **只清除** 该平台字典中的 `api_key`（置 `""` 或移除键后写回）。
- **不删除** 整份平台配置，也不删除 `api_base_url`、region、auth 等字段。

迁移时机：`PlatformConfigStore` 初始化 `load()` 路径中执行，每个平台最多有效迁移一次（成功后 plist 已空，后续无操作）。

## 错误处理

| 场景 | 行为 |
|------|------|
| Keychain 保存失败 | 不更新内存中的已保存 Key 状态为成功；不清除 plist 旧值（若仍在迁移）；可日志 |
| Keychain 读取失败 | 若 UserDefaults 仍有明文则走迁移分支；否则该平台未配置（`isConfigured == false`） |
| 自启 register 失败 | 菜单不勾选 + Alert |
| 自启 unregister 失败 | Alert；下次开菜单再以系统 status 刷新 |

## 测试计划

1. **KeychainStore**：set → get；update；delete；空 account 行为。
2. **迁移**：UserDefaults 有 Key、Keychain 无 → load 后 Keychain 有、UserDefaults `api_key` 为空。
3. **迁移失败**：模拟 Keychain set 抛错 → UserDefaults 明文仍在。
4. **setAPIKey**：Keychain 有值且 defaults 中 `api_key` 为空。
5. **resetAPIKey**：Keychain 无条目且 defaults 为空。
6. **LaunchAtLoginService**：对 protocol mock 测菜单勾选与调用 `setEnabled`；真实 `SMAppService` 可作为手动/集成验证。
7. 现有 `PlatformConfigStoreTests` / `ConfigServiceTests` 适配 Keychain 注入，避免测到真实钥匙串或互相污染。

## 文件变更（预期）

| 文件 | 变更 |
|------|------|
| `Services/KeychainStore.swift` | 新增 |
| `Services/LaunchAtLoginService.swift` | 新增 |
| `Services/Platforms/PlatformConfigStore.swift` | Key 改走 Keychain + 迁移清除 |
| `StatusBar/StatusBarController.swift` | 开机自启菜单项 |
| `Resources/en.json` / `zh-Hans.json` | 文案 |
| `Tests/...` | Keychain、迁移、自启相关测试 |
| `project.yml` | 若需显式链接 `ServiceManagement`（通常系统框架自动） |

## 验收标准

1. 右键菜单可开关开机自启，勾选状态与系统登录项一致。
2. 配置 API Key 后，`com.quota.statusbar.plist` 对应平台 `api_key` 为空；Keychain 中存在对应 account 条目。
3. 升级后首次启动：旧 plist 明文 Key 被迁入 Keychain 并清除。
4. 重启 Mac 后再次打开 QuotaBar，已配置平台仍为已配置，无需重填 Key。
5. 单元测试覆盖迁移与清除语义。
