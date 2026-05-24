# Multi-Platform Model Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable users to enable/disable multiple AI platforms and configure each platform's API credentials through a unified settings panel.

**Architecture:** Convert the existing single-active-platform model to a multi-enabled-platform model with checkbox-based selection. Each platform can be individually enabled/disabled and configured. The status bar shows aggregated usage from all enabled platforms, or the user can switch between platforms.

**Tech Stack:** Swift, SwiftUI, AppKit, UserDefaults

---

## Overview of Changes

### Before (Current)
- Single active platform at a time
- Platform switching via right-click menu
- No way to disable a platform without configuring another

### After (Target)
- All available platforms are pre-defined (MiniMax, DeepSeek, future platforms)
- **用户勾选/取消勾选**来启用/禁用平台，无需手动添加
- 用户只能从已有平台列表中选择，不能添加自定义平台
- 每个启用的平台可单独配置 API
- 右键菜单和 Popover 都提供勾选框交互

---

## File Structure

```
Services/
  ConfigService.swift           # Modify: add enabledPlatforms list (stores user's checkbox selections)
  PlatformManager.swift        # Modify: support multiple enabled platforms

Models/
  PlatformType.swift            # Modify: add isEnabled property (per-platform enable state)

Views/
  PlatformSelectionView.swift   # Create: checkbox list for platform selection
  PopoverContentView.swift     # Modify: integrate platform selection UI

StatusBar/
  StatusBarController.swift     # Modify: right-click menu with checkboxes
```

**关键设计：所有平台在代码中预定义（PlatformType.allCases），用户通过勾选框选择启用哪些平台，无需手动添加。**

---

## Task 1: Add isEnabled to PlatformType

**Files:**
- Modify: `Services/Platforms/PlatformConfigStore.swift` (add extension to PlatformType)

- [ ] **Step 1: Add `isEnabled` computed property to PlatformType**

In `PlatformConfigStore.swift`, add an extension to PlatformType:

```swift
extension PlatformType {
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "quotabar.platform.\(rawValue).enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "quotabar.platform.\(rawValue).enabled") }
    }
}
```

**设计说明：** 每个 PlatformType 直接存储自己的启用状态，无需额外列表。用户勾选即启用，取消勾选即禁用。

---

## Task 2: Add Helper to Get Enabled Platforms

**Files:**
- Modify: `Services/ConfigService.swift`

- [ ] **Step 1: Add `allEnabledPlatforms` computed property**

Add to ConfigService.swift:

```swift
var allEnabledPlatforms: [PlatformType] {
    PlatformType.allCases.filter { $0.isEnabled }
}
```

**设计说明：** 无需维护单独的列表，直接从各平台的 isEnabled 状态计算得出。

---

## Task 3: Add Toggle Method and Notification

**Files:**
- Modify: `Services/Platforms/PlatformManager.swift`

- [ ] **Step 1: Add NotificationCenter notification name**

Add at top of PlatformManager.swift:

```swift
extension Notification.Name {
    static let platformEnabledChanged = Notification.Name("platformEnabledChanged")
}
```

- [ ] **Step 2: Add method to toggle platform enabled state**

```swift
func setPlatformEnabled(_ enabled: Bool, for platform: PlatformType) {
    UserDefaults.standard.set(enabled, forKey: "quotabar.platform.\(platform.rawValue).enabled")
    NotificationCenter.default.post(name: .platformEnabledChanged, object: nil)
}
```

**Note:** Using UserDefaults directly because PlatformType is a value type (enum) - setting `platform.isEnabled = enabled` would cause a compile error since enums cannot be mutated through a let parameter.

**设计说明：** 简单的状态切换方法，更新 PlatformType.isEnabled 后发送通知。

---

## Task 4: Update PlatformViewModel to Observe Changes

**Files:**
- Modify: `ViewModels/PlatformViewModel.swift`

- [ ] **Step 1: Add observer for platform enabled changes**

In init(), add:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(onPlatformEnabledChanged),
    name: .platformEnabledChanged,
    object: nil
)
```

Add method:

```swift
@objc private func onPlatformEnabledChanged() {
    objectWillChange.send()
}
```

**设计说明：** 观察者模式，平台启用状态变化时通知 SwiftUI 刷新视图。

---

## Task 5: Add Checkbox Menu to Right-Click Menu

**Files:**
- Modify: `StatusBar/StatusBarController.swift`

- [ ] **Step 1: Modify the right-click menu to show checkboxes**

In `showDisplaySettingsSubmenu()`, replace the platform switching section with checkbox items:

```swift
// Platform Enable/Disable submenu
let platformMenu = NSMenu()

// Add checkbox items for each platform
for platform in PlatformType.allCases {
    let item = NSMenuItem(title: platform.displayName, action: #selector(togglePlatformEnabled(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = platform
    item.state = platform.isEnabled ? .on : .off
    platformMenu.addItem(item)
}

let platformItem = NSMenuItem(title: I18nService.shared.translate("menu.platforms"), action: nil, keyEquivalent: "")
platformItem.submenu = platformMenu
rootMenu.insertItem(platformItem, at: 2)  // After Display Settings
```

- [ ] **Step 2: Add toggle action method**

```swift
@objc private func togglePlatformEnabled(_ sender: NSMenuItem) {
    guard let platform = sender.representedObject as? PlatformType else { return }
    let newState = !platform.isEnabled
    PlatformManager.shared.setPlatformEnabled(newState, for: platform)
    sender.state = newState ? .on : .off
}
```

**设计说明：** 右键菜单中每个平台显示为勾选框项，用户可以直接勾选/取消勾选来启用/禁用平台。

---

## Task 6: Create PlatformSelectionView

**Files:**
- Create: `Views/PlatformSelectionView.swift`

- [ ] **Step 1: Create the view with checkboxes**

Create `Views/PlatformSelectionView.swift`:

```swift
import SwiftUI

struct PlatformSelectionView: View {
    @ObservedObject var viewModel: PlatformViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Platforms")
                .font(.headline)
                .padding(.bottom, 8)

            ForEach(PlatformType.allCases, id: \.self) { platform in
                Toggle(isOn: Binding(
                    get: { platform.isEnabled },
                    set: { newValue in
                        PlatformManager.shared.setPlatformEnabled(newValue, for: platform)
                    }
                )) {
                    Text(platform.displayName)
                        .font(.body)
                }
                .toggleStyle(.checkbox)
            }

            Spacer()
        }
        .padding()
        .frame(width: 250, height: 180)
    }
}
```

**设计说明：** 简单的勾选框列表，用户勾选即启用，取消勾选即禁用。不需要手动添加平台。

---

## Task 7: Integrate PlatformSelectionView into Popover

**Files:**
- Modify: `Views/PopoverContentView.swift`

- [ ] **Step 1: Add platform selection button**

Add to the header section (before the platform tabs):

```swift
Button(action: { showPlatformSelection = true }) {
    Image(systemName: "checkmark.circle")
        .foregroundColor(.secondary)
}
.popover(isPresented: $showPlatformSelection) {
    PlatformSelectionView(viewModel: viewModel)
}
```

- [ ] **Step 2: Add state variable**

Add property:

```swift
@State private var showPlatformSelection = false
```

**设计说明：** Popover 顶部有一个勾选图标按钮，点击弹出平台选择视图。

---

## Task 8: Add Default Enabled State for New Platforms

**Files:**
- Modify: `Services/Platforms/PlatformConfigStore.swift` (PlatformType extension)

- [ ] **Step 1: Ensure MiniMax is enabled by default on first launch**

In the `isEnabled` extension, set a default for MiniMax:

```swift
var isEnabled: Bool {
    get {
        if UserDefaults.standard.object(forKey: "quotabar.platform.\(rawValue).enabled") == nil {
            return self == .minimax  // Only MiniMax enabled by default
        }
        return UserDefaults.standard.bool(forKey: "quotabar.platform.\(rawValue).enabled")
    }
    set { UserDefaults.standard.set(newValue, forKey: "quotabar.platform.\(rawValue).enabled") }
}
```

**设计说明：** 首次启动时，只有 MiniMax 默认启用，其他平台默认禁用。新平台加入时也默认禁用，由用户勾选启用。

---

## Task 9: Build and Test

- [ ] **Step 1: Generate project and build**

Run: `xcodegen generate && xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Test right-click menu checkboxes**

1. Run the app
2. Right-click status bar item
3. Find "Platforms" submenu
4. Verify MiniMax is checked, DeepSeek is unchecked (default)
5. Click to toggle DeepSeek on
6. Verify state persists after app restart

- [ ] **Step 3: Test Popover platform selection**

1. Left-click status bar item (open popover)
2. Find the checkmark icon button in header
3. Click to open PlatformSelectionView
4. Toggle platforms on/off
5. Verify changes reflect in right-click menu

---

## Migration Notes

**No breaking changes:** Existing user configurations will be preserved. The default behavior maintains backward compatibility:
- If no platforms are explicitly enabled, MiniMax is enabled by default
- Active platform switching continues to work as before
- Right-click menu structure is extended, not replaced

---

## Plan complete and saved to `docs/superpowers/plans/2026-05-24-multi-platform-selection.md`

**Two execution options:**

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**