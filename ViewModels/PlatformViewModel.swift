import Foundation
import SwiftUI
import Combine

@MainActor
protocol PlatformViewModelDelegate: AnyObject {
    func platformViewModel(_ viewModel: PlatformViewModel, didUpdateData data: PlatformUsageData?)
    func platformViewModel(_ viewModel: PlatformViewModel, didSwitchPlatform platform: PlatformType)
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

    // MARK: - Platform Enabled Observer

    @objc private func onPlatformEnabledChanged() {
        // When platform enabled state changes, ensure active platform is still valid
        if !activePlatform.isEnabled {
            // Current active platform was disabled, switch to first enabled platform
            if let firstEnabled = configService.allEnabledPlatforms.first {
                switchActivePlatform(firstEnabled)
            }
        }
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

    func fetchAllUsage() {
        fetchTask?.cancel()
        fetchTask = Task {
            let results = await platformManager.fetchAllUsage()

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

            // Notify delegate for active platform
            delegate?.platformViewModel(self, didUpdateData: platformData[activePlatform])
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
        showingConfig = true
    }

    func saveAPIKey() {
        guard let platform = configPlatform else { return }
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        let store = configService.store(for: platform)
        store.setAPIKey(trimmedKey)
        store.setRegion(regionInput)

        showingConfig = false
        configPlatform = nil
        apiKeyInput = ""
        regionInput = "domestic"

        fetchUsage(for: platform)
    }

    func cancelConfig() {
        showingConfig = false
        configPlatform = nil
        apiKeyInput = ""
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
