import Foundation

struct KimiLimitsResponse: Codable {
    let limits: [KimiLimitItem]?
    let usage: KimiUsage?
}

struct KimiLimitItem: Codable {
    let detail: KimiLimitDetail?
}

struct KimiLimitDetail: Codable {
    let limit: Double?
    let remaining: Double?
    let resetTime: String?
}

struct KimiUsage: Codable {
    let limit: Double?
    let remaining: Double?
    let resetTime: String?
}

final class KimiPlatformAPIService: PlatformAPIService {
    let platformType: PlatformType = .kimi

    private let cacheTimeout: TimeInterval = 10
    private var cache: (data: PlatformUsageData, timestamp: Date)?

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = cache, Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.data
        }

        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(.kimi)
        }

        guard let url = URL(string: config.apiBaseURL) else {
            throw PlatformError.invalidResponse(.kimi)
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
            throw PlatformError.networkError(.kimi, error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.invalidResponse(.kimi)
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw PlatformError.unauthorized(.kimi)
        }

        guard httpResponse.statusCode == 200 else {
            throw PlatformError.networkError(.kimi, "HTTP \(httpResponse.statusCode)")
        }

        let kimiResponse: KimiLimitsResponse
        do {
            kimiResponse = try JSONDecoder().decode(KimiLimitsResponse.self, from: data)
        } catch {
            throw PlatformError.decodingError(.kimi, error.localizedDescription)
        }

        var metrics: [UsageMetric] = []

        // Parse 5-hour window from limits
        if let limits = kimiResponse.limits {
            for limitItem in limits {
                if let detail = limitItem.detail,
                   let limitValue = detail.limit,
                   let remaining = detail.remaining {
                    let used = max(limitValue - remaining, 0)
                    let resetTime = parseResetTime(detail.resetTime)
                    metrics.append(UsageMetric(
                        label: "five_hour",
                        currentValue: used,
                        totalValue: limitValue,
                        unit: "times",
                        resetTime: resetTime
                    ))
                    break // Only take first limit item for 5-hour window
                }
            }
        }

        // Parse weekly limit from usage
        if let usage = kimiResponse.usage,
           let limitValue = usage.limit,
           let remaining = usage.remaining {
            let used = max(limitValue - remaining, 0)
            let resetTime = parseResetTime(usage.resetTime)
            metrics.append(UsageMetric(
                label: "weekly_limit",
                currentValue: used,
                totalValue: limitValue,
                unit: "times",
                resetTime: resetTime
            ))
        }

        let isHealthy = !metrics.isEmpty

        let usageData = PlatformUsageData(
            platform: .kimi,
            displayName: "Kimi",
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

    private func parseResetTime(_ resetTimeString: String?) -> Date? {
        guard let timeString = resetTimeString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timeString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timeString)
    }
}