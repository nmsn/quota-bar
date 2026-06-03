# Release Process

## Overview

版本发布流程，包含版本号更新、GitHub Release 创建、DMG 打包与上传。

## Prerequisites

- `gh` CLI 已登录 (`gh auth login`)
- XcodeGen 已安装
- macOS 环境

---

## Full Release Flow

### 1. 合并功能 PR

功能开发完成后，通过 PR 合并到 `main` 分支。

```bash
# 切换到 main 并拉取最新代码
git checkout main
git pull origin main
```

### 2. 创建版本更新 PR

`main` 分支受保护，必须通过 PR 更新版本号。

```bash
# 创建版本更新分支
git checkout -b chore/bump-version-X.Y.Z

# 更新版本号 (在 project.pbxproj 中)
# MARKETING_VERSION: X.Y.Z (显示版本)
# CURRENT_PROJECT_VERSION: N (构建版本，每次 +1)

# 提交并推送
git add -A
git commit -m "chore: bump version to X.Y.Z"
git push origin chore/bump-version-X.Y.Z

# 创建 PR
gh pr create --base main --head chore/bump-version-X.Y.Z \
  --title "chore: bump version to X.Y.Z" \
  --body "## Summary\n\nBump version to X.Y.Z\n\n## Changes\n\n- MARKETING_VERSION: X.Y.Z-1 → X.Y.Z\n- CURRENT_PROJECT_VERSION: N → N+1"
```

### 3. 合并版本 PR

在 GitHub 网页合并 PR，或使用 CLI：

```bash
gh pr merge PR_NUMBER --admin --merge
```

### 4. 推送 Tag

```bash
git checkout main
git pull origin main

# 创建 tag
git tag -a vX.Y.Z -m "vX.Y.Z"

# 推送 tag (触发 GitHub Release)
git push origin vX.Y.Z
```

> **注意**: 如果 Release 页面没有自动创建，需要手动创建（见步骤 5）。

### 5. 创建 GitHub Release

如果 tag push 后没有自动创建 Release：

```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z" \
  --notes "## vX.Y.Z\n\n### Changes\n\n- ..."
```

### 6. 构建 Release 版本

```bash
xcodebuild -project minimax-bar.xcodeproj \
  -scheme minimax-bar \
  -configuration Release \
  build
```

构建产物位于:
```
~/Library/Developer/Xcode/DerivedData/quota-bar-*/Build/Products/Release/QuotaBar.app
```

### 7. 打包 DMG

使用 `create-dmg`（需先安装：`brew install create-dmg`）:

```bash
./scripts/package-dmg.sh
```

打包产物位于: `dist/QuotaBar-X.Y.Z.dmg`

### 8. 上传 DMG 到 Release

```bash
gh release upload vX.Y.Z QuotaBar-X.Y.Z.dmg --clobber
```

### 9. 验证 Release

```bash
gh release view vX.Y.Z --json assets --jq '.assets'
```

---

## 版本号规则

| 类型 | 何时使用 | 示例 |
|------|---------|------|
| **MAJOR** | 不兼容的 API 变更 | 1.0.0 → 2.0.0 |
| **MINOR** | 向后兼容的重大功能 | 1.0.0 → 1.1.0 |
| **PATCH** | 向后兼容的 bug 修复 | 1.0.0 → 1.0.1 |

**CURRENT_PROJECT_VERSION** 每次发布 +1，与 MARKETING_VERSION 独立递增。

---

## 常见问题

### Q: main 分支受保护，如何推送？

所有对 `main` 的更改必须通过 PR。创建 `chore/bump-version-X.Y.Z` 分支，通过 PR 合并。

### Q: DMG 打包失败 (无此文件或目录)？

Xcode build 产物在 DerivedData 中，使用完整路径：

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/minimax-bar-*/Build/Products/Release -name "QuotaBar.app" -type d | head -1)
hdiutil create -volname QuotaBar -srcfolder "$APP_PATH" -ov -format UDZO -o QuotaBar-X.Y.Z.dmg
```

### Q: 是否需要签名？

本地测试不需要签名。正式分发建议使用 Developer ID 签名：

```bash
codesign --force --sign "Developer ID Application: YOUR_NAME" --deep QuotaBar-X.Y.Z.dmg
```

### Q: Sparkle 自动更新配置？

详见 [sparkle-integration.md](./sparkle-integration.md)。

---

## Release Checklist

- [ ] 功能 PR 已合并到 main
- [ ] 版本号已更新 (MARKETING_VERSION + CURRENT_PROJECT_VERSION)
- [ ] 版本更新 PR 已合并
- [ ] Tag vX.Y.Z 已推送
- [ ] GitHub Release 已创建并填写 changelog
- [ ] DMG 已构建
- [ ] DMG 已上传到 Release
- [ ] Release 页面可下载 DMG
