import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var viewModel: PlatformViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        I18nService.shared.loadTranslations()

        viewModel = PlatformViewModel()
        guard let viewModel else { return }

        statusBarController = StatusBarController(viewModel: viewModel)
        viewModel.delegate = self
        viewModel.startAutoRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.cleanup()
    }
}

extension AppDelegate: PlatformViewModelDelegate {
    func platformViewModel(_ viewModel: PlatformViewModel, didUpdateData data: PlatformUsageData?) {
        statusBarController?.update(data: data)
    }

    func platformViewModel(_ viewModel: PlatformViewModel, didUpdateAllData allData: [PlatformType: PlatformUsageData]) {
        statusBarController?.updateAll(data: allData)
    }

    func platformViewModel(_ viewModel: PlatformViewModel, didSwitchPlatform platform: PlatformType) {
        // Platform switched, status bar will update via didUpdateData
    }
}
