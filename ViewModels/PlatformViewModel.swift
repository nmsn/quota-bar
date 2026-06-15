import Foundation
import SwiftUI
import Combine

@MainActor
protocol PlatformViewModelDelegate: AnyObject {
    func platformViewModel(_ viewModel: PlatformViewModel, didUpdateData data: PlatformUsageData?)
    func platformViewModel(_ viewModel: PlatformViewModel, didSwitchPlatform platform: PlatformType)
    // 全量数据更新 (所有平台). 默认空实现, 向后兼容.
    func platformViewModel(_ viewModel: PlatformViewModel, didUpdateAllData allData: [PlatformType: PlatformUsageData])
}

extension PlatformViewModelDelegate {
    func platformViewModel(_ viewModel: PlatformViewModel, didUpdateAllData allData: [PlatformType: PlatformUsageData]) {}
}

@MainActor
final class PlatformViewModel: ObservableObject {
    @Published var platformData: [PlatformType: PlatformUsageData] = [:]
    @Published var platformErrors: [PlatformType: PlatformError] = [:]
    @Published var isLoading: [PlatformType: Bool] = [:]
    @Published var activePlatform: PlatformType
    @Published var showingConfig: Bool = false
    @Published var configPlatform: PlatformType?
    @Published var apiKeyInput: String = ""
    @Published var regionInput: String = "domestic"
    @Published var showingAPIKey: Bool = false
    // StepFun 用账号密码登录, 单独的输入状态
    @Published var usernameInput: String = ""
    @Published var passwordInput: String = ""

    weak var delegate: PlatformViewModelDelegate?

    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?
    private let platformManager: PlatformManager
    private let configService: ConfigService

    init(platformManager: PlatformManager = .shared, configService: ConfigService = .shared) {
        self.platformManager = platformManager
        self.configService = configService
        self.activePlatform = configService.activePlatform

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onPlatformEnabledChanged),
            name: .platformEnabledChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Platform Enabled Observer

    @objc private func onPlatformEnabledChanged() {
        // When platform enabled state changes, ensure active platform is still valid
        let enabledPlatforms = configService.allEnabledPlatforms

        if !activePlatform.isEnabled {
            // Current active platform was disabled, switch to first enabled platform
            if let firstEnabled = enabledPlatforms.first {
                switchActivePlatform(firstEnabled)
            }
        } else if !enabledPlatforms.contains(activePlatform) {
            // Active platform not in enabled list, switch to first enabled
            if let firstEnabled = enabledPlatforms.first {
                switchActivePlatform(firstEnabled)
            }
        }
        // If newly enabled platform is not the active one, switch to it
        // This handles the case where user enables a new platform via checkbox
        objectWillChange.send()
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        let interval = configService.refreshInterval.timeInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchAllUsage()
            }
        }
        Task {
            await fetchAllUsage()
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func restartAutoRefresh() {
        startAutoRefresh()
    }

    // MARK: - Fetch

    func fetchAllUsage() async {
        fetchTask?.cancel()
        fetchTask = Task {
            // 先标记所有已配置平台为加载中
            for platform in platformManager.configuredPlatforms() {
                isLoading[platform] = true
            }

            let results = await platformManager.fetchAllUsage()

            // 被新的 fetchAllUsage 取消时丢弃结果, 避免覆盖更新的数据
            // (PlatformManager 的 TaskGroup 不检查 cancellation, 网络请求会跑完,
            //  但结果不再写回, 防止定时刷新和手动刷新撞车时旧数据盖新数据)
            if Task.isCancelled { return }

            for (platform, result) in results {
                switch result {
                case .success(let data):
                    platformData[platform] = data
                    platformErrors[platform] = nil
                case .failure(let error):
                    if let platformError = error as? PlatformError {
                        platformErrors[platform] = platformError
                    } else {
                        platformErrors[platform] = .networkError(platform, error.localizedDescription)
                    }
                }
                isLoading[platform] = false
            }

            // Notify delegate for active platform + 全量数据 (钉选多平台状态栏需要)
            delegate?.platformViewModel(self, didUpdateData: platformData[activePlatform])
            delegate?.platformViewModel(self, didUpdateAllData: platformData)
        }
    }

    func fetchUsage(for platform: PlatformType) {
        isLoading[platform] = true
        platformErrors[platform] = nil

        Task {
            do {
                let data = try await platformManager.fetchUsage(for: platform)
                platformData[platform] = data
                platformErrors[platform] = nil

                if platform == activePlatform {
                    delegate?.platformViewModel(self, didUpdateData: data)
                }
                delegate?.platformViewModel(self, didUpdateAllData: platformData)
            } catch {
                if let platformError = error as? PlatformError {
                    platformErrors[platform] = platformError
                } else {
                    platformErrors[platform] = .networkError(platform, error.localizedDescription)
                }
            }
            isLoading[platform] = false
        }
    }

    // MARK: - Platform Switching

    func switchActivePlatform(_ platform: PlatformType) {
        activePlatform = platform
        configService.activePlatform = platform
        delegate?.platformViewModel(self, didSwitchPlatform: platform)
        delegate?.platformViewModel(self, didUpdateData: platformData[platform])
    }

    // MARK: - Config

    func configureAPIKey(for platform: PlatformType) {
        configPlatform = platform
        let store = configService.store(for: platform)
        apiKeyInput = store.isConfigured ? (store.apiKey ?? "") : ""
        regionInput = store.region
        showingAPIKey = false
        // StepFun: apiKey 存的是 "手机号\n密码", 拆开填到专用输入框
        if platform == .stepfun {
            let parts = (store.apiKey ?? "")
                .components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            usernameInput = parts.first ?? ""
            passwordInput = parts.count > 1 ? parts[1] : ""
        } else {
            usernameInput = ""
            passwordInput = ""
        }
        showingConfig = true
    }

    func saveAPIKey() {
        guard let platform = configPlatform else { return }
        let store = configService.store(for: platform)

        // StepFun: 存 "手机号\n密码" 组合, service 里解析登录
        if platform == .stepfun {
            let username = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty, !password.isEmpty else { return }
            store.setAPIKey("\(username)\n\(password)")
            store.setRegion(regionInput)
        } else {
            let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { return }
            store.setAPIKey(trimmedKey)
            store.setRegion(regionInput)
        }

        showingConfig = false
        configPlatform = nil
        apiKeyInput = ""
        usernameInput = ""
        passwordInput = ""
        regionInput = "domestic"

        fetchUsage(for: platform)
    }

    func cancelConfig() {
        showingConfig = false
        configPlatform = nil
        apiKeyInput = ""
        usernameInput = ""
        passwordInput = ""
        regionInput = "domestic"
        showingAPIKey = false
    }

    // MARK: - Computed

    var activePlatformData: PlatformUsageData? {
        platformData[activePlatform]
    }

    var activePlatformError: PlatformError? {
        platformErrors[activePlatform]
    }

    var isActivePlatformLoading: Bool {
        isLoading[activePlatform] ?? false
    }

    var allConfiguredPlatforms: [PlatformType] {
        platformManager.configuredPlatforms()
    }

    var allPlatforms: [PlatformType] {
        ConfigService.shared.allEnabledPlatforms
    }

    func isConfigured(_ platform: PlatformType) -> Bool {
        configService.store(for: platform).isConfigured
    }

    func platformDisplayName(_ platform: PlatformType) -> String {
        platform.displayName
    }

    // MARK: - Cleanup

    func cleanup() {
        fetchTask?.cancel()
        stopAutoRefresh()
    }
}
