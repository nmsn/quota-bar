# QuotaBar Sparkle 集成

## 密钥信息

- **EdDSA 公钥**: `8n6qpNCw5nnChaXomz88SKWPaYUXfvSo8P9fMpq/6hs=`
  - 此公钥可公开（无安全风险），用于验证更新签名的合法性
- **私钥位置**: Mac Keychain 中（与公钥配对）
- **警告**: 私钥一旦删除将无法解密已有更新，务必妥善保管

## 状态机（UpdateService.State）

UI（右键菜单的"检查更新"项）根据这个 5 态状态机展示标题：

| 状态 | 触发条件 | 菜单标题 (en / zh-Hans) | tooltip |
|------|---------|------------------------|---------|
| `idle` | 初始 / 无检查过 | `Check for Updates` / `检查更新` | (无) |
| `checking` | 用户点击检查 或 Sparkle 自动检查中 | `Checking for Updates…` / `检查更新中…` | 上次检查时间 |
| `upToDate` | `SPUUpdaterDelegate.updaterDidNotFindUpdate` 回调 | `Up to Date` / `已是最新` | 上次检查时间 |
| `updateAvailable` | `willInstallUpdate` 回调（Sparkle 弹窗出现）| `Update Available` / `有可用更新` | 上次检查时间 |
| `failed(String)` | `didAbortWithError` 回调 | `Check Failed` / `检查失败` | 上次检查时间 |

`lastCheckDate` 通过 KVO 监听 `SPUUpdater.lastUpdateCheckDate` 自动同步，无需手动维护。

## 发布更新步骤

### 1. 构建 Release 版本

```bash
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -configuration Release build
```

### 2. 打包为 .dmg 格式

使用 `Disk Utility` 或命令行创建 .dmg：

```bash
hdiutil create -volname QuotaBar \
  -srcfolder ~/Library/Developer/Xcode/DerivedData/quota-bar-*/Build/Products/Release/QuotaBar.app \
  -ov -format UDZO QuotaBar.dmg
```

### 3. 对 .dmg 进行签名（可选但推荐）

使用 Developer ID 签名：

```bash
codesign --force --sign "Developer ID Application: YOUR_NAME" --deep QuotaBar.dmg
```

### 4. 创建 GitHub Release

1. 访问 GitHub 仓库的 [Releases 页面](https://github.com/nmsn/quota-bar/releases)
2. 点击 "Draft a new release"
3. 填写版本号（如 `v2.0.2`）
4. 上传 `.dmg` 文件
5. 发布 Release

### 5. 配置 Appcast

`appcast.xml` 托管在 `gh-pages` 分支，通过 GitHub Pages 暴露：

- URL: `https://nmsn.github.io/quota-bar/appcast.xml`
- 在 `App/Info.plist` 的 `SUFeedURL` 里配置

更新 `gh-pages` 分支的 `appcast.xml`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>QuotaBar Updates</title>
    <link>https://nmsn.github.io/quota-bar/appcast.xml</link>
    <item>
      <title>Version 2.0.2</title>
      <pubDate>Tue, 02 Jun 2026 18:00:00 +0800</pubDate>
      <enclosure url="https://github.com/nmsn/quota-bar/releases/download/v2.0.2/QuotaBar-2.0.2.dmg"
                 sparkle:version="2.0.2" length="1234567" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

注意：`length` 必须是 DMG 文件**实际字节数**（用 `ls -la` 或 `stat -f "%z"` 查看），Sparkle 校验失败会拒绝更新。

## Sparkle 密钥生成（如果需要重新生成）

```bash
# 路径可能在 DerivedData 中
~/Library/Developer/Xcode/DerivedData/quota-bar-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

## 相关文件

- `Services/UpdateService.swift` — Sparkle 状态机 + delegate + KVO 桥接
- `StatusBar/StatusBarController.swift` — 右键菜单动态 title / tooltip / Cmd+U
- `App/Info.plist` — `SUFeedURL` 指向 appcast
- `project.yml:43` — `SUPublicEDKey` 配置
