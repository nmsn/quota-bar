import Foundation

final class MiniMaxPlatformAPIService: PlatformAPIService {
    let platformType: PlatformType = .minimax_cn

    private let cacheTimeout: TimeInterval = 10
    private var cache: (data: PlatformUsageData, timestamp: Date)?

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = cache, Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.data
        }

        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(config.platformType)
        }

        let baseURL = apiBaseURL(for: config)
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(config.platformType)
        }

        guard let url = URL(string: baseURL) else {
            throw PlatformError.invalidResponse(config.platformType)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("\(config.authPrefix)\(config.apiKey)", forHTTPHeaderField: config.authHeader)
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
            let responseString = String(data: data, encoding: .utf8) ?? "unable to decode"
            throw PlatformError.networkError(config.platformType, "HTTP \(httpResponse.statusCode): \(responseString.prefix(200))")
        }

        let apiResponse: APIResponse
        do {
            apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw PlatformError.decodingError(config.platformType, error.localizedDescription)
        }

        guard let modelData = apiResponse.modelRemains?.first(where: { $0.modelName == "general" }) else {
            throw PlatformError.invalidResponse(config.platformType)
        }

        let usageData = parseUsageData(from: modelData, platform: config.platformType)
        cache = (usageData, Date())
        return usageData
    }

    func clearCache() {
        cache = nil
    }

    private func apiBaseURL(for config: PlatformConfigData) -> String {
        let region = config.region ?? "domestic"
        if region == "international" {
            return config.apiBaseURLInternational ?? config.apiBaseURL
        }
        return config.apiBaseURL
    }

    private func parseUsageData(from model: ModelRemain, platform: PlatformType) -> PlatformUsageData {
        // 新接口: remaining_percent (0-100), 转换为已用百分比
        let dailyRemainingPct = model.currentIntervalRemainingPercent ?? 0
        let weeklyRemainingPct = model.currentWeeklyRemainingPercent ?? 0

        let dailyUsedPct = 100.0 - dailyRemainingPct
        let weeklyUsedPct = 100.0 - weeklyRemainingPct

        // 重置时间: 新接口用绝对时间戳(毫秒), 旧接口用相对毫秒
        let now = Date()
        let dailyResetTime: Date?
        if let endTimeMs = model.endTime, endTimeMs > 0 {
            dailyResetTime = Date(timeIntervalSince1970: Double(endTimeMs) / 1000.0)
        } else if let remainsMs = model.remainsTime, remainsMs > 0 {
            dailyResetTime = now.addingTimeInterval(Double(remainsMs) / 1000.0)
        } else {
            dailyResetTime = nil
        }

        let weeklyResetTime: Date?
        if let weeklyEndTimeMs = model.weeklyEndTime, weeklyEndTimeMs > 0 {
            weeklyResetTime = Date(timeIntervalSince1970: Double(weeklyEndTimeMs) / 1000.0)
        } else if let weeklyRemainsMs = model.weeklyRemainsTime, weeklyRemainsMs > 0 {
            weeklyResetTime = now.addingTimeInterval(Double(weeklyRemainsMs) / 1000.0)
        } else {
            weeklyResetTime = nil
        }

        let isHealthy = dailyRemainingPct < 15.0

        return PlatformUsageData(
            platform: platform,
            displayName: platform.displayName,
            metrics: [
                UsageMetric(label: "five_hour", currentValue: dailyRemainingPct, totalValue: 100, unit: "requests", resetTime: dailyResetTime),
                UsageMetric(label: "weekly_limit", currentValue: weeklyRemainingPct, totalValue: 100, unit: "requests", resetTime: weeklyResetTime)
            ],
            lastUpdated: Date(),
            isHealthy: isHealthy
        )
    }
}
