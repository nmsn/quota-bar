import Foundation

extension Notification.Name {
    static let platformEnabledChanged = Notification.Name("platformEnabledChanged")
}

final class PlatformManager {
    static let shared = PlatformManager()

    private var services: [PlatformType: PlatformAPIService] = [:]
    let networkService: NetworkService
    private let configService: ConfigService

    init(networkService: NetworkService = URLSessionNetworkService(), configService: ConfigService = .shared) {
        self.networkService = networkService
        self.configService = configService

        // Register default platform services
        register(MiniMaxPlatformAPIService())
        register(DeepSeekPlatformAPIService())
        register(GLMPlatformAPIService())
        register(KimiPlatformAPIService())
    }

    func register(_ service: PlatformAPIService) {
        services[service.platformType] = service
    }

    func fetchUsage(for platform: PlatformType) async throws -> PlatformUsageData {
        guard let service = services[platform] else {
            throw PlatformError.notConfigured(platform)
        }

        let store = configService.store(for: platform)
        guard store.isConfigured else {
            throw PlatformError.notConfigured(platform)
        }

        return try await service.fetchUsage(config: store.toConfigData(), network: networkService)
    }

    func fetchAllUsage() async -> [PlatformType: Result<PlatformUsageData, Error>] {
        var results: [PlatformType: Result<PlatformUsageData, Error>] = [:]

        await withTaskGroup(of: (PlatformType, Result<PlatformUsageData, Error>).self) { group in
            for platform in PlatformType.allCases {
                let store = configService.store(for: platform)
                guard store.isConfigured else { continue }

                group.addTask { [weak self] in
                    do {
                        let data = try await self?.fetchUsage(for: platform)
                        if let data {
                            return (platform, .success(data))
                        } else {
                            return (platform, .failure(PlatformError.notConfigured(platform)))
                        }
                    } catch {
                        return (platform, .failure(error))
                    }
                }
            }

            for await (platform, result) in group {
                results[platform] = result
            }
        }

        return results
    }

    func configuredPlatforms() -> [PlatformType] {
        configService.configuredPlatforms()
    }

    func clearCache(for platform: PlatformType) {
        services[platform]?.clearCache()
    }

    func clearAllCaches() {
        services.values.forEach { $0.clearCache() }
    }

    func setPlatformEnabled(_ enabled: Bool, for platform: PlatformType) {
        // Prevent disabling the last enabled platform
        if !enabled && platform.isEnabled && isLastEnabledPlatform(platform) {
            return
        }
        UserDefaults.standard.set(enabled, forKey: "quotabar.platform.\(platform.rawValue).enabled")
        NotificationCenter.default.post(name: .platformEnabledChanged, object: nil)
    }

    func isLastEnabledPlatform(_ platform: PlatformType) -> Bool {
        PlatformType.allCases.filter { $0.isEnabled }.count <= 1 && platform.isEnabled
    }
}
