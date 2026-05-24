import Foundation

enum PlatformType: String, Codable, CaseIterable, Hashable {
    case minimax
    case deepseek
    case glm
    case kimi

    var displayName: String {
        switch self {
        case .minimax: return "MiniMax"
        case .deepseek: return "DeepSeek"
        case .glm: return "GLM"
        case .kimi: return "Kimi"
        }
    }
}

enum PlatformError: Error, Equatable {
    case notConfigured(PlatformType)
    case invalidResponse(PlatformType)
    case networkError(PlatformType, String)
    case unauthorized(PlatformType)
    case decodingError(PlatformType, String)
}

extension PlatformError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return I18nService.shared.translate("error.notConfigured")
        case .invalidResponse:
            return I18nService.shared.translate("error.invalidResponse")
        case .networkError(_, let message):
            return String(format: I18nService.shared.translate("error.networkError"), message)
        case .unauthorized:
            return I18nService.shared.translate("error.unauthorized")
        case .decodingError(_, let message):
            return String(format: I18nService.shared.translate("error.networkError"), message)
        }
    }
}

struct PlatformUsageData: Equatable {
    let platform: PlatformType
    let displayName: String
    let metrics: [UsageMetric]
    let lastUpdated: Date
    let isHealthy: Bool
}

struct UsageMetric: Equatable {
    let label: String
    let currentValue: Double
    let totalValue: Double?
    let unit: String
    let resetTime: Date?
}

struct PlatformConfigData {
    let platformType: PlatformType
    let apiBaseURL: String
    let authHeader: String
    let authPrefix: String
    let apiKey: String
    var region: String?  // "domestic" or "international"
    var apiBaseURLInternational: String?
}

protocol NetworkService {
    func data(from request: URLRequest) async throws -> (Data, URLResponse)
}

class URLSessionNetworkService: NetworkService {
    func data(from request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

protocol PlatformAPIService {
    var platformType: PlatformType { get }
    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData
    func clearCache()
}

enum RefreshInterval: String, Codable, CaseIterable {
    case thirtySeconds
    case oneMinute
    case threeMinutes
    case fiveMinutes
    case tenMinutes

    var timeInterval: TimeInterval {
        switch self {
        case .thirtySeconds: return 30
        case .oneMinute: return 60
        case .threeMinutes: return 180
        case .fiveMinutes: return 300
        case .tenMinutes: return 600
        }
    }

    var i18nKey: String {
        switch self {
        case .thirtySeconds: return "menu.refresh.30s"
        case .oneMinute: return "menu.refresh.1m"
        case .threeMinutes: return "menu.refresh.3m"
        case .fiveMinutes: return "menu.refresh.5m"
        case .tenMinutes: return "menu.refresh.10m"
        }
    }

    static let `default`: RefreshInterval = .oneMinute
}
