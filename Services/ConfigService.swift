import Foundation

enum DisplayMode: String, Codable {
    case used
    case remaining
}

final class ConfigService {
    static let shared = ConfigService()

    private var cachedDisplayMode: DisplayMode = .used
    private var cachedActivePlatform: PlatformType = .minimax_cn
    private var cachedRefreshInterval: RefreshInterval = .default
    private var platformStores: [PlatformType: PlatformConfigStore] = [:]
    // platformStores 被 fetchAllUsage 的并发任务同时读写, 必须加锁保护字典结构.
    private let storesLock = NSLock()
    // cached 全局配置可能在多线程下读写 (UI 主线程 + 切换平台), 加锁保护.
    private let configLock = NSLock()

    private init() {
        loadGlobalConfig()
        cleanupLegacyPlatformKeys()
    }

    // MARK: - Global Config

    var displayMode: DisplayMode {
        get { configLock.lock(); defer { configLock.unlock() }; return cachedDisplayMode }
        set {
            configLock.lock()
            cachedDisplayMode = newValue
            configLock.unlock()
            saveGlobalConfig()
        }
    }

    var activePlatform: PlatformType {
        get { configLock.lock(); defer { configLock.unlock() }; return cachedActivePlatform }
        set {
            configLock.lock()
            cachedActivePlatform = newValue
            configLock.unlock()
            saveGlobalConfig()
        }
    }

    var refreshInterval: RefreshInterval {
        get { configLock.lock(); defer { configLock.unlock() }; return cachedRefreshInterval }
        set {
            configLock.lock()
            cachedRefreshInterval = newValue
            configLock.unlock()
            saveGlobalConfig()
        }
    }

    // MARK: - Platform Stores

    func store(for platform: PlatformType) -> PlatformConfigStore {
        storesLock.lock()
        defer { storesLock.unlock() }
        if let existing = platformStores[platform] {
            return existing
        }
        let store = PlatformConfigStore(platformType: platform)
        platformStores[platform] = store
        return store
    }

    func configuredPlatforms() -> [PlatformType] {
        PlatformType.allCases.filter { store(for: $0).isConfigured }
    }

    var allEnabledPlatforms: [PlatformType] {
        PlatformType.allCases.filter { $0.isEnabled }
    }

    // MARK: - Private

    private func loadGlobalConfig() {
        if let raw = UserDefaults.standard.string(forKey: "quotabar.displayMode"),
           let mode = DisplayMode(rawValue: raw) {
            cachedDisplayMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: "quotabar.activePlatform"),
           let platform = PlatformType(rawValue: raw) {
            cachedActivePlatform = platform
        }
        if let raw = UserDefaults.standard.string(forKey: "quotabar.refreshInterval"),
           let interval = RefreshInterval(rawValue: raw) {
            cachedRefreshInterval = interval
        }
    }

    private func saveGlobalConfig() {
        UserDefaults.standard.set(cachedDisplayMode.rawValue, forKey: "quotabar.displayMode")
        UserDefaults.standard.set(cachedActivePlatform.rawValue, forKey: "quotabar.activePlatform")
        UserDefaults.standard.set(cachedRefreshInterval.rawValue, forKey: "quotabar.refreshInterval")
    }

    /// 清理已从 PlatformType 删除的平台的残留 UserDefaults 配置 (minimax_en / glm_en / kimi).
    /// 这些 key 是历史版本写入的, enum 里已无对应 case, 留着是无害的死数据, 顺手清掉.
    private func cleanupLegacyPlatformKeys() {
        for legacy in ["minimax_en", "glm_en", "kimi"] {
            let prefix = "quotabar.platform.\(legacy)"
            UserDefaults.standard.removeObject(forKey: prefix)
            UserDefaults.standard.removeObject(forKey: "\(prefix).enabled")
            UserDefaults.standard.removeObject(forKey: "\(prefix).pinned")
        }
    }
}
