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

- Pages CDN: `https://nmsn.github.io/quota-bar/appcast.xml`（可能有缓存延迟）
- 即时校验用 raw: `https://raw.githubusercontent.com/nmsn/quota-bar/gh-pages/appcast.xml`
- 在 `App/Info.plist` 的 `SUFeedURL` 里配置（指向 Pages URL）

更新 `gh-pages` 分支的 `appcast.xml`（推荐用脚本，见下节）：

```xml
<item>
  <title>Version 2.0.4</title>
  <pubDate>Thu, 16 Jul 2026 10:58:00 +0800</pubDate>
  <enclosure url="https://github.com/nmsn/quota-bar/releases/download/v2.0.4/QuotaBar-2.0.4.dmg"
             sparkle:version="5"
             sparkle:shortVersionString="2.0.4"
             length="1407629"
             type="application/octet-stream"/>
</item>
```

注意：`length` 必须是 DMG 文件**实际字节数**（用 `ls -la` 或 `stat -f "%z"` 查看），Sparkle 校验失败会拒绝更新。

**Never** put marketing `X.Y.Z` into `sparkle:version` — that field must be the integer build number.

## Version fields

| Field | Meaning | Example |
|-------|---------|---------|
| `sparkle:version` / `CFBundleVersion` | Monotonic build integer | `5` |
| `sparkle:shortVersionString` / `CFBundleShortVersionString` | Marketing version | `2.0.4` |

## Updating appcast with script

Use `scripts/update-appcast.sh` (wraps `scripts/update_appcast.py`) against a local `gh-pages` checkout.

**Insert** a new item (newest first):

```bash
./scripts/update-appcast.sh \
  --marketing 2.0.4 \
  --build 5 \
  --dmg dist/QuotaBar-2.0.4.dmg \
  --appcast /path/to/gh-pages/appcast.xml
```

**Replace** an existing enclosure by its current `sparkle:version` (e.g. fix a bad marketing-as-version entry):

```bash
./scripts/update-appcast.sh \
  --marketing 2.0.4 \
  --build 5 \
  --dmg dist/QuotaBar-2.0.4.dmg \
  --appcast /path/to/gh-pages/appcast.xml \
  --replace-enclosure-version 2.0.4
```

After human approval, commit and push `gh-pages`. Verify via the raw URL that `sparkle:version` is an integer and `sparkle:shortVersionString` is set.

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
