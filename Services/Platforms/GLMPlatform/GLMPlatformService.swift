import Foundation

struct GLMLimitInfo: Codable {
    let type: String
    let percentage: Int?
    let usage: Int?
    let currentValue: Int?
    let remaining: Int?
}

struct GLMUsageResponse: Codable {
    let code: Int
    let msg: String
    let data: GLMUsageData?
    let success: Bool
}

struct GLMUsageData: Codable {
    let limits: [GLMLimitInfo]?
    let level: String?
}

final class GLMPlatformAPIService: PlatformAPIService {
    let platformType: PlatformType = .glm_cn

    private let cacheTimeout: TimeInterval = 10
    private var cache: (data: PlatformUsageData, timestamp: Date)?

    private func apiBaseURL(for config: PlatformConfigData) -> String {
        let region = config.region ?? "domestic"
        if region == "international" {
            return config.apiBaseURLInternational ?? config.apiBaseURL
        }
        return config.apiBaseURL
    }

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = cache, Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.data
        }

        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(config.platformType)
        }

        let baseURL = apiBaseURL(for: config)
        guard let url = URL(string: baseURL) else {
            throw PlatformError.invalidResponse(config.platformType)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.apiKey, forHTTPHeaderField: config.authHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await network.data(from: request)
        } catch {
            throw PlatformError.networkError(config.platformType, error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.invalidResponse(config.platformType)
        }

        if httpResponse.statusCode == 401 {
            throw PlatformError.unauthorized(config.platformType)
        }

        guard httpResponse.statusCode == 200 else {
            throw PlatformError.networkError(config.platformType, "HTTP \(httpResponse.statusCode)")
        }

        let usageResponse: GLMUsageResponse
        do {
            usageResponse = try JSONDecoder().decode(GLMUsageResponse.self, from: data)
        } catch {
            throw PlatformError.decodingError(config.platformType, error.localizedDescription)
        }

        var metrics: [UsageMetric] = []

        if let limits = usageResponse.data?.limits {
            for limit in limits {
                if limit.type == "TIME_LIMIT", let remaining = limit.remaining, let usage = limit.usage {
                    metrics.append(UsageMetric(
                        label: "five_hour",
                        currentValue: Double(remaining),
                        totalValue: Double(usage),
                        unit: "times",
                        resetTime: nil
                    ))
                } else if limit.type == "TOKENS_LIMIT", let percentage = limit.percentage {
                    metrics.append(UsageMetric(
                        label: "weekly_limit",
                        currentValue: Double(100 - percentage),
                        totalValue: 100,
                        unit: "%",
                        resetTime: nil
                    ))
                }
            }
        }

        let isHealthy = usageResponse.success && !metrics.isEmpty

        let usageData = PlatformUsageData(
            platform: config.platformType,
            displayName: config.platformType.displayName,
            metrics: metrics,
            lastUpdated: Date(),
            isHealthy: isHealthy
        )

        cache = (usageData, Date())
        return usageData
    }

    func clearCache() {
        cache = nil
    }
}