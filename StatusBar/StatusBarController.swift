import AppKit
import SwiftUI

@MainActor
class StatusBarController {
    private static let minimumItemWidth: CGFloat = 40

    private var statusItem: NSStatusItem
    private var statusBarView: RightClickStatusBarView
    private let viewModel: PlatformViewModel
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
        rootMenu.addItem(platformItem)
        rootMenu.addItem(languageItem)
        rootMenu.addItem(NSMenuItem.separator())

        let checkUpdateItem = NSMenuItem(title: I18nService.shared.translate("menu.checkUpdate"), action: #selector(checkUpdateAction), keyEquivalent: "")
        checkUpdateItem.target = self
        rootMenu.addItem(checkUpdateItem)

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
