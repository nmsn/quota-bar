import AppKit
import SwiftUI

@MainActor
class StatusBarController {
    private static let minimumItemWidth: CGFloat = 36

    private var statusItem: NSStatusItem
    private var statusBarView: RightClickStatusBarView
    private let viewModel: PlatformViewModel
    private var popover: NSPopover?
    private var clickMonitor: Any?

    // 钉选多平台: 每个钉选平台一个独立的 NSStatusItem, 常驻状态栏.
    private var pinnedItems: [PlatformType: NSStatusItem] = [:]
    private var pinnedViews: [PlatformType: RightClickStatusBarView] = [:]

    init(viewModel: PlatformViewModel) {
        self.viewModel = viewModel

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let statusBarContentView = StatusBarView(platformData: viewModel.activePlatformData)
        statusBarView = RightClickStatusBarView(rootView: statusBarContentView)

        guard let button = statusItem.button else {
            return
        }

        button.frame.size.height = NSStatusBar.system.thickness
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusBarView)
        NSLayoutConstraint.activate([
            statusBarView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            statusBarView.topAnchor.constraint(equalTo: button.topAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        statusBarView.onLeftClick = { [weak self] in
            self?.statusItemClicked()
        }

        statusBarView.onRightClick = { [weak self] in
            self?.showDisplaySettingsSubmenu(from: nil)
        }

        statusBarView.layoutSubtreeIfNeeded()
        let fittedWidth = max(
            StatusBarController.minimumItemWidth,
            ceil(statusBarView.fittingSize.width)
        )
        statusItem.length = fittedWidth

        // 钉选平台监听: 平台启用状态或钉选状态变化时重建 item
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlatformChanged),
            name: .platformEnabledChanged,
            object: nil
        )

        // 初始化时构建钉选 item
        rebuildPinnedItems()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Click Handling

    private func setupClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopoverIfNeeded()
            }
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func closePopoverIfNeeded() {
        guard let popover = popover, popover.isShown else { return }
        popover.performClose(nil)
        self.popover = nil
        removeClickMonitor()
    }

    private func statusItemClicked(from button: NSStatusBarButton? = nil) {
        // 优先用传入的 button, 否则用主 statusItem 的; 钉选模式下找第一个可见的 pinned item
        let targetButton = button
            ?? statusItem.button
            ?? pinnedItems.values.compactMap { $0.isVisible ? $0.button : nil }.first
        guard let targetButton else { return }

        if let existingPopover = popover, existingPopover.isShown {
            existingPopover.performClose(nil)
            popover = nil
            removeClickMonitor()
            return
        }

        let popoverContentView = PopoverContentView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: popoverContentView)
        let newPopover = NSPopover()
        newPopover.contentViewController = hostingController
        newPopover.behavior = .applicationDefined
        newPopover.show(relativeTo: targetButton.bounds, of: targetButton, preferredEdge: .minY)

        DispatchQueue.main.async {
            hostingController.view.window?.makeFirstResponder(hostingController.view)
        }

        popover = newPopover
        setupClickMonitor()
    }

    // MARK: - Right Click Menu

    private func showDisplaySettingsSubmenu(from item: NSStatusItem? = nil) {
        closePopoverIfNeeded()

        // Display Settings submenu
        let displayMenu = NSMenu()

        let usedItem = NSMenuItem(title: I18nService.shared.translate("menu.showUsed"), action: #selector(setDisplayModeUsed), keyEquivalent: "")
        usedItem.target = self
        usedItem.state = ConfigService.shared.displayMode == .used ? .on : .off
        displayMenu.addItem(usedItem)

        let remainingItem = NSMenuItem(title: I18nService.shared.translate("menu.showRemaining"), action: #selector(setDisplayModeRemaining), keyEquivalent: "")
        remainingItem.target = self
        remainingItem.state = ConfigService.shared.displayMode == .remaining ? .on : .off
        displayMenu.addItem(remainingItem)

        let displaySettingsItem = NSMenuItem(title: I18nService.shared.translate("menu.displaySettings"), action: nil, keyEquivalent: "")
        displaySettingsItem.submenu = displayMenu

        // Refresh Interval submenu
        let refreshMenu = NSMenu()
        for interval in RefreshInterval.allCases {
            let item = NSMenuItem(
                title: I18nService.shared.translate(interval.i18nKey),
                action: #selector(setRefreshInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = interval.rawValue
            item.state = interval == ConfigService.shared.refreshInterval ? .on : .off
            refreshMenu.addItem(item)
        }
        let refreshItem = NSMenuItem(title: I18nService.shared.translate("menu.refreshInterval"), action: nil, keyEquivalent: "")
        refreshItem.submenu = refreshMenu

        // Platform Enable/Disable submenu
        let platformMenu = NSMenu()

        // 每个平台一个子菜单, 含「启用」+「固定到状态栏」两个选项
        for platform in PlatformType.allCases {
            let platSubmenu = NSMenu()

            let enableItem = NSMenuItem(
                title: I18nService.shared.translate("menu.platformEnabled"),
                action: #selector(togglePlatformEnabled(_:)),
                keyEquivalent: ""
            )
            enableItem.target = self
            enableItem.representedObject = platform
            enableItem.state = platform.isEnabled ? .on : .off
            platSubmenu.addItem(enableItem)

            let pinItem = NSMenuItem(
                title: I18nService.shared.translate("menu.pinToStatusBar"),
                action: #selector(togglePlatformPinned(_:)),
                keyEquivalent: ""
            )
            pinItem.target = self
            pinItem.representedObject = platform
            pinItem.state = platform.isPinned ? .on : .off
            // 未启用的平台不能钉选
            pinItem.isEnabled = platform.isEnabled
            platSubmenu.addItem(pinItem)

            let platItem = NSMenuItem(title: platform.displayName, action: nil, keyEquivalent: "")
            platItem.submenu = platSubmenu
            platformMenu.addItem(platItem)
        }

        platformMenu.addItem(NSMenuItem.separator())
        let configureItem = NSMenuItem(title: I18nService.shared.translate("menu.configurePlatform"), action: #selector(showConfigMenu), keyEquivalent: "")
        configureItem.target = self
        platformMenu.addItem(configureItem)

        let platformItem = NSMenuItem(title: I18nService.shared.translate("menu.platforms"), action: nil, keyEquivalent: "")
        platformItem.submenu = platformMenu

        // Language submenu
        let languageMenu = NSMenu()
        let isEnglish = I18nService.shared.currentLocale == "en"

        let englishItem = NSMenuItem(title: I18nService.shared.translate("menu.lang.en"), action: #selector(setLanguageEnglish), keyEquivalent: "")
        englishItem.target = self
        englishItem.state = isEnglish ? .on : .off
        languageMenu.addItem(englishItem)

        let chineseItem = NSMenuItem(title: I18nService.shared.translate("menu.lang.zh"), action: #selector(setLanguageChinese), keyEquivalent: "")
        chineseItem.target = self
        chineseItem.state = !isEnglish ? .on : .off
        languageMenu.addItem(chineseItem)

        let languageItem = NSMenuItem(title: I18nService.shared.translate("menu.language"), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu

        // Root menu
        let rootMenu = NSMenu()
        // 立即刷新: 清所有平台缓存(token/usage)重新拉取, 平台偶发卡住时一键自愈.
        let refreshNowItem = NSMenuItem(title: I18nService.shared.translate("menu.refreshNow"), action: #selector(refreshAllNow), keyEquivalent: "")
        refreshNowItem.target = self
        rootMenu.addItem(refreshNowItem)
        rootMenu.addItem(NSMenuItem.separator())
        rootMenu.addItem(displaySettingsItem)
        rootMenu.addItem(refreshItem)
        rootMenu.addItem(platformItem)
        rootMenu.addItem(languageItem)
        rootMenu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(
            title: I18nService.shared.translate("menu.about"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        rootMenu.addItem(aboutItem)

        rootMenu.addItem(NSMenuItem.separator())

        let checkUpdateItem = NSMenuItem(
            title: titleForUpdateState(),
            action: #selector(checkUpdateAction),
            keyEquivalent: "u"
        )
        checkUpdateItem.keyEquivalentModifierMask = .command
        checkUpdateItem.target = self
        checkUpdateItem.isEnabled = UpdateService.shared.canCheckForUpdates
        checkUpdateItem.toolTip = tooltipForUpdateState()
        rootMenu.addItem(checkUpdateItem)

        let openReleasesItem = NSMenuItem(
            title: I18nService.shared.translate("update.openReleases"),
            action: #selector(openReleasesAction),
            keyEquivalent: ""
        )
        openReleasesItem.target = self
        rootMenu.addItem(openReleasesItem)

        rootMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: I18nService.shared.translate("menu.quit"), action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        rootMenu.addItem(quitItem)

        // 弹出菜单: 优先用传入的 item, 否则用主 statusItem.
        // 钉选模式下主 statusItem 被隐藏, 找第一个 pinned item 来弹.
        let targetItem = item ?? statusItem
        if targetItem.isVisible || item != nil {
            targetItem.menu = rootMenu
            targetItem.button?.performClick(nil)
            targetItem.menu = nil
        } else {
            // 主 item 隐藏了, 用第一个 pinned item
            if let firstPinned = pinnedItems.values.first(where: { $0.isVisible }) {
                firstPinned.menu = rootMenu
                firstPinned.button?.performClick(nil)
                firstPinned.menu = nil
            }
        }
    }

    // MARK: - Actions

    @objc private func switchPlatform(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let platform = PlatformType(rawValue: rawValue) else { return }
        viewModel.switchActivePlatform(platform)
        updateStatusBarView()
    }

    @objc private func togglePlatformEnabled(_ sender: NSMenuItem) {
        guard var platform = sender.representedObject as? PlatformType else { return }
        let newState = !platform.isEnabled
        // 禁用平台前先取消钉选 (必须在 setPlatformEnabled 之前, 因为它同步发通知触发 rebuildPinnedItems)
        if !newState && platform.isPinned {
            platform.isPinned = false
        }
        PlatformManager.shared.setPlatformEnabled(newState, for: platform)
        sender.state = newState ? .on : .off
    }

    @objc private func togglePlatformPinned(_ sender: NSMenuItem) {
        guard var platform = sender.representedObject as? PlatformType else { return }
        let newState = !platform.isPinned
        platform.isPinned = newState
        sender.state = newState ? .on : .off
        // 发通知触发 rebuildPinnedItems
        NotificationCenter.default.post(name: .platformEnabledChanged, object: nil)
    }

    @objc private func showConfigMenu() {
        viewModel.configureAPIKey(for: viewModel.activePlatform)
        statusItemClicked()
    }

    @objc private func setDisplayModeUsed() {
        ConfigService.shared.displayMode = .used
        updateStatusBarView()
    }

    @objc private func setDisplayModeRemaining() {
        ConfigService.shared.displayMode = .remaining
        updateStatusBarView()
    }

    @objc private func setRefreshInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let interval = RefreshInterval(rawValue: rawValue) else { return }
        ConfigService.shared.refreshInterval = interval
        viewModel.restartAutoRefresh()
    }

    // 一键自愈: 清掉所有平台的 token/usage 缓存并立即重新拉取.
    // 某平台(尤其 StepFun)因 token 过期/网络偶发卡住显示异常时, 右键点这个即可恢复.
    // 先停定时刷新, 避免定时触发的 fetchAllUsage cancel 掉这次手动拉取 (cancel 后
    // 结果会被 fetchAllUsage 的 Task.isCancelled 丢弃, 表现为"刷新没反应").
    @objc private func refreshAllNow() {
        PlatformManager.shared.clearAllCaches()
        viewModel.stopAutoRefresh()
        Task { @MainActor [weak self] in
            await self?.viewModel.fetchAllUsage()
            self?.viewModel.startAutoRefresh()
        }
    }

    @objc private func setLanguageEnglish() {
        I18nService.shared.setLocale("en")
        updateStatusBarView()
    }

    @objc private func setLanguageChinese() {
        I18nService.shared.setLocale("zh-Hans")
        updateStatusBarView()
    }

    @objc private func checkUpdateAction() {
        UpdateService.shared.checkForUpdates()
    }

    @objc private func openReleasesAction() {
        UpdateService.shared.openReleasesPage()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "QuotaBar"
        alert.informativeText = String(
            format: I18nService.shared.translate("menu.about.version"),
            AppVersion.marketingVersion,
            Calendar.current.component(.year, from: Date())
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: I18nService.shared.translate("menu.about.ok"))
        alert.addButton(withTitle: I18nService.shared.translate("menu.about.openReleases"))
        alert.icon = NSImage(named: NSImage.applicationIconName)

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            UpdateService.shared.openReleasesPage()
        }
    }

    /// 根据 UpdateService.State 返回菜单项 title, 状态文案优先, idle 状态用通用文案
    private func titleForUpdateState() -> String {
        let key: String
        switch UpdateService.shared.state {
        case .idle:
            return I18nService.shared.translate("menu.checkUpdate")
        case .checking:
            key = "update.checking"
        case .upToDate:
            key = "update.upToDate"
        case .updateAvailable:
            key = "update.updateAvailable"
        case .failed:
            key = "update.checkFailed"
        }
        return I18nService.shared.translate(key)
    }

    /// "Last checked: 2 hours ago" — i18n 模板 + Date.formatted relative 渲染
    private func tooltipForUpdateState() -> String? {
        guard let date = UpdateService.shared.lastCheckDate else { return nil }
        let template = I18nService.shared.translate("update.lastChecked")
        let relative = date.formatted(.relative(presentation: .named))
        return String(format: template, relative)
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Update

    private func updateStatusBarView() {
        statusBarView.update(rootView: StatusBarView(
            platformData: viewModel.activePlatformData,
            displayMode: ConfigService.shared.displayMode
        ))
        statusBarView.layoutSubtreeIfNeeded()
    }

    // 单平台数据更新 (兼容旧 delegate 回调).
    func update(data: PlatformUsageData?) {
        updateAll(data: viewModel.platformData)
    }

    // 全量更新: 同时刷新主 item 和所有钉选 item.
    // allData 是所有平台的数据字典.
    func updateAll(data allData: [PlatformType: PlatformUsageData]) {
        let pinned = PlatformType.allPinned

        // 有钉选平台: 主 item 隐藏, 只用 pinned items 显示
        if !pinned.isEmpty {
            statusItem.length = 0
            statusItem.isVisible = false

            for platform in pinned {
                updatePinnedItem(platform, data: allData[platform])
            }
            return
        }

        // 没有钉选平台: 主 item 显示 activePlatform (原有行为)
        statusItem.isVisible = true
        statusBarView.update(rootView: StatusBarView(
            platformData: viewModel.activePlatformData,
            displayMode: ConfigService.shared.displayMode
        ))
        statusBarView.layoutSubtreeIfNeeded()
        statusItem.length = max(
            StatusBarController.minimumItemWidth,
            ceil(statusBarView.fittingSize.width)
        )
    }

    // 更新单个钉选 item 的内容.
    private func updatePinnedItem(_ platform: PlatformType, data: PlatformUsageData?) {
        guard let view = pinnedViews[platform] else { return }

        view.update(rootView: StatusBarView(
            platformData: data,
            displayMode: ConfigService.shared.displayMode
        ))
        view.layoutSubtreeIfNeeded()

        if let item = pinnedItems[platform] {
            item.length = max(
                StatusBarController.minimumItemWidth,
                ceil(view.fittingSize.width)
            )
        }
    }

    // MARK: - Pinned Items Management

    // 平台启用/钉选状态变化时, 重建钉选 item 列表.
    @objc private func handlePlatformChanged() {
        rebuildPinnedItems()
        updateAll(data: viewModel.platformData)
        // 主动拉取刚钉选但还没有数据的平台, 避免新 pin 的块一直显示 "--"
        for platform in PlatformType.allPinned where viewModel.platformData[platform] == nil {
            viewModel.fetchUsage(for: platform)
        }
    }

    // 根据当前 isPinned 状态, 增删 NSStatusItem.
    private func rebuildPinnedItems() {
        let pinned = Set(PlatformType.allPinned)
        let existing = Set(pinnedItems.keys)

        // 移除不再钉选的
        for platform in existing.subtracting(pinned) {
            if let item = pinnedItems.removeValue(forKey: platform) {
                NSStatusBar.system.removeStatusItem(item)
            }
            pinnedViews.removeValue(forKey: platform)
        }

        // 新增刚钉选的
        for platform in PlatformType.allPinned where !existing.contains(platform) {
            createPinnedItem(for: platform)
        }
    }

    private func createPinnedItem(for platform: PlatformType) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let view = RightClickStatusBarView(rootView: StatusBarView(
            platformData: viewModel.platformData[platform],
            displayMode: ConfigService.shared.displayMode
        ))

        guard let button = item.button else { return }
        button.frame.size.height = NSStatusBar.system.thickness
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        // 点击任意一块都打开弹出面板, 传入该 item 自己的 button 用于 popover 定位
        view.onLeftClick = { [weak self, weak item] in
            self?.statusItemClicked(from: item?.button)
        }
        // 右键菜单: 用被点击的 item 自己的 button 弹出菜单
        view.onRightClick = { [weak self, weak item] in
            self?.showDisplaySettingsSubmenu(from: item)
        }

        view.layoutSubtreeIfNeeded()
        item.length = max(
            StatusBarController.minimumItemWidth,
            ceil(view.fittingSize.width)
        )

        pinnedItems[platform] = item
        pinnedViews[platform] = view
    }
}
