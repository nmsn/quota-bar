import AppKit
import SwiftUI

@MainActor
class StatusBarController {
    private static let minimumItemWidth: CGFloat = 36

    private var statusItem: NSStatusItem
    private var statusBarView: RightClickStatusBarView
    private let viewModel: PlatformViewModel
    private let launchAtLoginService: LaunchAtLoginServing = LaunchAtLoginService()
    private var popover: NSPopover?
    private var clickMonitor: Any?

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
            self?.showDisplaySettingsSubmenu()
        }

        statusBarView.layoutSubtreeIfNeeded()
        let fittedWidth = max(
            StatusBarController.minimumItemWidth,
            ceil(statusBarView.fittingSize.width)
        )
        statusItem.length = fittedWidth
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

    private func statusItemClicked() {
        guard let button = statusItem.button else { return }

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
        newPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        DispatchQueue.main.async {
            hostingController.view.window?.makeFirstResponder(hostingController.view)
        }

        popover = newPopover
        setupClickMonitor()
    }

    // MARK: - Right Click Menu

    private func showDisplaySettingsSubmenu() {
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

        let launchAtLoginItem = NSMenuItem(
            title: I18nService.shared.translate("menu.launchAtLogin"),
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = launchAtLoginService.isEnabled ? .on : .off

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
        rootMenu.addItem(displaySettingsItem)
        rootMenu.addItem(refreshItem)
        rootMenu.addItem(launchAtLoginItem)
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

        statusItem.menu = rootMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Actions

    @objc private func switchPlatform(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let platform = PlatformType(rawValue: rawValue) else { return }
        viewModel.switchActivePlatform(platform)
        updateStatusBarView()
    }

    @objc private func togglePlatformEnabled(_ sender: NSMenuItem) {
        guard let platform = sender.representedObject as? PlatformType else { return }
        let newState = !platform.isEnabled
        PlatformManager.shared.setPlatformEnabled(newState, for: platform)
        sender.state = newState ? .on : .off
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
        // Clear menu so next right-click rebuilds from system status
        statusItem.menu = nil
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

    func update(data: PlatformUsageData?) {
        statusBarView.update(rootView: StatusBarView(
            platformData: data,
            displayMode: ConfigService.shared.displayMode
        ))
        statusBarView.layoutSubtreeIfNeeded()
        statusItem.length = max(
            StatusBarController.minimumItemWidth,
            ceil(statusBarView.fittingSize.width)
        )
    }
}
