import Foundation

final class MiniMaxPlatformAPIService: PlatformAPIService {
    let platformType: PlatformType = .minimax

    private let cacheTimeout: TimeInterval = 10
    private var cache: (data: PlatformUsageData, timestamp: Date)?

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = cache, Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.data
        }

        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(.minimax)
        }

        let baseURL = apiBaseURL(for: config)
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(.minimax)
        }

        guard let url = URL(string: baseURL) else {
            throw PlatformError.invalidResponse(.minimax)
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
            throw PlatformError.networkError(.minimax, error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.invalidResponse(.minimax)
        }

        if httpResponse.statusCode == 401 {
            throw PlatformError.unauthorized(.minimax)
        }

        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "unable to decode"
            throw PlatformError.networkError(.minimax, "HTTP \(httpResponse.statusCode): \(responseString.prefix(200))")
        }

        let apiResponse: APIResponse
        do {
            apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw PlatformError.decodingError(.minimax, error.localizedDescription)
        }

        guard let modelData = apiResponse.modelRemains?.first else {
            throw PlatformError.invalidResponse(.minimax)
        }

        let usageData = parseUsageData(from: modelData)
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

    private func parseUsageData(from model: ModelRemain) -> PlatformUsageData {
        let dailyTotal = Double(model.currentIntervalTotalCount ?? 0)
        let dailyUsed = Double(model.currentIntervalUsageCount ?? 0)
        let weeklyTotal = Double(model.currentWeeklyTotalCount ?? 0)
        let weeklyUsed = Double(model.currentWeeklyUsageCount ?? 0)

        let resetMs = model.remainsTime ?? 0
        let weeklyResetMs = model.weeklyRemainsTime ?? 0
        let now = Date()

        let dailyResetTime = resetMs > 0 ? now.addingTimeInterval(Double(resetMs) / 1000.0) : nil
        let weeklyResetTime = weeklyResetMs > 0 ? now.addingTimeInterval(Double(weeklyResetMs) / 1000.0) : nil

        let dailyPercentage = dailyTotal > 0 ? (dailyTotal - dailyUsed) / dailyTotal : 0
        let isHealthy = dailyPercentage < 0.85

        return PlatformUsageData(
            platform: .minimax,
            displayName: "MiniMax",
            metrics: [
                UsageMetric(label: "five_hour", currentValue: dailyUsed, totalValue: dailyTotal, unit: "requests", resetTime: dailyResetTime),
                UsageMetric(label: "weekly_limit", currentValue: weeklyUsed, totalValue: weeklyTotal, unit: "requests", resetTime: weeklyResetTime)
            ],
            lastUpdated: Date(),
            isHealthy: isHealthy
        )
    }
}
