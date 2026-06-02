# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# QuotaBar

A macOS menu bar app displaying AI platform API usage/quota statistics. Built with SwiftUI + AppKit hybrid architecture. Supports multiple platforms (MiniMax, DeepSeek).

## Build Commands

```bash
# Generate Xcode project
xcodegen generate

# Debug build
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -configuration Debug build

# Release build
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -configuration Release build

# Run tests
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -destination 'platform=macOS' test

# Package as DMG
hdiutil create -volname QuotaBar -srcfolder build/Release/QuotaBar.app -ov -format UDZO -o QuotaBar.dmg
```

## Architecture

- **Menu bar app** (LSUIElement=true, no dock icon)
- **SwiftUI + AppKit hybrid**: SwiftUI views inside NSStatusItem via NSHostingController
- **Protocol-based multi-platform architecture**: each platform implements `PlatformAPIService` protocol

### Directory Structure

| Directory | Purpose |
|-----------|---------|
| `App/` | Entry point (`main.swift`, `AppDelegate.swift`), Info.plist |
| `Models/` | Data models (`PlatformProtocol.swift` - core types, `UsageData.swift` - legacy) |
| `Services/` | Business logic |
| `Services/Platforms/` | Platform-specific services |
| `Services/Platforms/MiniMaxPlatform/` | MiniMax API service |
| `Services/Platforms/DeepSeekPlatform/` | DeepSeek API service |
| `Services/Platforms/PlatformManager.swift` | Orchestrates all platform services |
| `Services/Platforms/PlatformConfigStore.swift` | Per-platform config file management |
| `Services/ConfigService.swift` | Global config (display mode, active platform, locale) |
| `Services/NetworkService.swift` | Network abstraction for testability |
| `StatusBar/` | Menu bar UI - `StatusBarController` manages NSStatusItem |
| `ViewModels/` | `PlatformViewModel` - manages multiple platform data |
| `Views/` | SwiftUI views - `PopoverContentView`, `StatusBarView` |
| `Tests/` | Unit tests with mocks |
| `Resources/ConfigTemplates/` | Config templates for each platform |

### Key Protocols

- `PlatformAPIService` - each platform implements this for API calls
- `NetworkService` - network abstraction (URLSession wrapper for testability)
- `PlatformType` - enum identifying supported platforms

### Key Patterns

- **StatusBarController** creates NSStatusItem, adds subview via `button.addSubview(statusBarView)`
- **RightClickStatusBarView** intercepts clicks via override, emits callbacks for left/right click
- **Popover** shown relative to status bar button bounds with `.minY` edge
- **Platform switching** via right-click menu or popover tabs
- **I18nService** uses JSON files in Resources (`en.json`, `zh-Hans.json`), locale stored in ConfigService

## Adding a New Platform

1. Add case to `PlatformType` enum in `Models/PlatformProtocol.swift`
2. Create config template in `Resources/ConfigTemplates/{platform}.template.json`
3. Create `Services/Platforms/{Platform}Platform/{Platform}PlatformService.swift` implementing `PlatformAPIService`
4. Register in `PlatformManager.init()`
5. Add I18n strings in `Resources/en.json` and `Resources/zh-Hans.json`
6. Write tests first (TDD)

## ⚠️ Human-in-the-Loop 原则 (强制)

**任何 commit / push / PR / Release 操作都必须经过人工确认**, Claude **禁止** 自主执行:

- ❌ 禁止未经用户确认就 `git commit` / `git push` / `gh pr create` / `gh pr merge` / `gh release create`
- ❌ 禁止未经用户确认就 `git tag` / `git push --tags` / 推 `gh-pages` 分支
- ❌ 禁止未经用户确认就删除远端分支 / 改动 `appcast.xml`
- ❌ 禁止在用户没看到 diff 的情况下自动 amend / rebase / force-push

**标准协作模式**:
1. Claude 完成代码 + 跑测试 + 自查 → 把**改动总结** (改了哪些文件 / 改了什么 / 测试结果) 呈现给用户
2. 用户审核 diff, 确认无误后**明确授权** "提交" / "push" / "开 PR" / "merge"
3. Claude 在得到明确指令后才执行对应的 git / gh 命令
4. PR 的 merge / Release 的创建是**用户最终行为** — 即使 Claude 建议了命令, 也由用户点击 GitHub UI 或亲自跑 `gh` 命令

**例外** (这些不需要逐步确认, 但应该在汇报里说明):
- 本地 `git status` / `git diff` / `git log` 等只读命令
- 构建 + 跑测试 (`xcodebuild ... test`)
- `curl` 等网络探测 (但避免向真实生产端点发送写操作)
- 删除 Claude 自己创建的临时文件 (worktree 等)

## Git Workflow

**main 分支受保护**, 修改代码必须通过 PR 合入:
1. 创建新分支或使用临时分支
2. **经过用户审核后** 提交更改并 push
3. **经过用户审核后** 通过 `gh pr create` 创建 PR
4. **用户** 使用 squash merge 合入 main (推荐在 GitHub UI 操作)

```bash
# 创建 PR (需用户授权)
gh pr create --title "description" --body "change details"

# Squash merge (由用户执行, 通常在 GitHub UI 点击按钮)
gh pr merge <pr-number> --squash
```

## Sparkle Update Release Process

1. Update `appcast.xml` on `gh-pages` branch with new version, date, and DMG URL
2. Create and push GitHub Release with the `.dmg` file
3. Ensure `length` attribute in appcast.xml matches actual DMG file size

```bash
git checkout gh-pages
# Edit appcast.xml item node
git add appcast.xml && git commit -m "Release vX.X.X" && git push origin gh-pages
```

## Tech Stack

- Swift 5.9, macOS 14.0+
- SwiftUI (views) + AppKit (NSStatusItem, NSPopover)
- [Sparkle](https://github.com/sparkle-project/Sparkle) 2.6.0+ for auto-update
- XcodeGen for project generation
- EdDSA signing key for update verification (public key in project.yml)
