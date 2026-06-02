import AppKit
import Foundation
import Sparkle

@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    /// 检查更新的状态机, UI 根据这个展示标题/颜色
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var canCheckForUpdates: Bool = false
    @Published private(set) var lastCheckDate: Date?

    private let updaterController: SPUStandardUpdaterController
    private let delegateProxy: UpdaterDelegateProxy
    private let releasesPageURL = URL(string: "https://github.com/nmsn/quota-bar/releases")!
    private var observations: [NSKeyValueObservation] = []

    // MARK: - Init

    private override init() {
        // SPUStandardUpdaterController 只在 init 时接受 updaterDelegate, 而那时 self 还没
        // 完成 NSObject 的 super.init, 所以传不进去. 用一个 proxy 类绕过:
        // proxy 持有一个回调, init 完成后我们把回调指向自己的 state setter.
        let proxy = UpdaterDelegateProxy()
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: proxy,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        self.delegateProxy = proxy
        super.init()
        proxy.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        observeSparkleState()
    }

    // MARK: - Public API

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        state = .checking
        updaterController.checkForUpdates(nil)
    }

    /// 检查失败 / 网络不通时的 fallback: 在浏览器打开 GitHub releases 页面
    func openReleasesPage() {
        NSWorkspace.shared.open(releasesPageURL)
    }

    // MARK: - State handling

    private func handle(_ event: UpdaterEvent) {
        switch event {
        case .noUpdate:
            state = .upToDate
        case .willInstall:
            state = .updateAvailable
        case .aborted(let message):
            state = .failed(message)
        }
    }

    // MARK: - KVO

    private func observeSparkleState() {
        let updater = updaterController.updater
        observations.append(
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.canCheckForUpdates = updater.canCheckForUpdates }
            }
        )
        observations.append(
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.lastCheckDate = updater.lastUpdateCheckDate }
            }
        )
    }
}

// MARK: - Delegate proxy

/// Sparkle 在 SPUStandardUpdaterController init 时就需要 SPUUpdaterDelegate,
/// 那时 UpdateService (NSObject 子类) 还没完成 super.init, 传不进去.
private enum UpdaterEvent {
    case noUpdate
    case willInstall
    case aborted(String)
}

/// 轻量 proxy, 把 SPUUpdaterDelegate 回调转换成闭包调用, UpdateService 在 super.init
/// 完成后把闭包接到自己的 state setter.
private final class UpdaterDelegateProxy: NSObject, SPUUpdaterDelegate {
    var onEvent: ((UpdaterEvent) -> Void)?

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        onEvent?(.noUpdate)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        onEvent?(.willInstall)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        onEvent?(.aborted(error.localizedDescription))
    }
}
