# QuotaBar

[English](./README.md) | 中文

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)
![Version](https://img.shields.io/github/v/release/nmsn/quota-bar)
![Downloads](https://img.shields.io/github/downloads/nmsn/quota-bar/total)

macOS 菜单栏应用，支持多平台 API 使用量查看（MiniMax、GLM、DeepSeek、Kimi）。

## 功能

- 多平台支持：MiniMax、GLM、DeepSeek、Kimi
- 实时显示日/周使用量百分比
- 动态图标颜色指示使用状态
  - 绿色：剩余 ≥ 50%
  - 黄色：剩余 10% ~ 50%
  - 红色：剩余 < 10%
- 左键点击打开详情 popover
- 右键菜单快速操作
- API Token 配置与管理
- Sparkle 自动更新支持

## 系统要求

- macOS 14.0 或更高版本

## 安装

1. 从 [Releases](https://github.com/nmsn/quota-bar/releases) 下载最新版本 `.dmg` 文件
2. 双击打开 DMG
3. 将 `QuotaBar` 拖入 Applications 文件夹
4. 首次运行时，右键点击应用选择"打开"

## 使用

1. 首次打开后，点击菜单栏图标
2. 在弹出窗口中点击右上角按钮配置 API Token
3. 选择平台并粘贴 Token
4. 菜单栏将实时显示使用量

## 开发

### 构建

```bash
# 安装依赖
xcodegen generate

# Debug 构建
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -configuration Debug build

# Release 构建
xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -configuration Release build
```

### 打包

```bash
hdiutil create -volname QuotaBar -srcfolder build/Release/QuotaBar.app -ov -format UDZO -o QuotaBar.dmg
```

## 技术栈

- Swift + SwiftUI
- AppKit (NSStatusItem, NSPopover)
- Sparkle (自动更新)
- XcodeGen (项目生成)

## License

MIT