import Foundation

struct DeepSeekBalanceInfo: Codable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

struct DeepSeekBalanceResponse: Codable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

final class DeepSeekPlatformAPIService: PlatformAPIService {
    let platformType: PlatformType = .deepseek

    private let cacheTimeout: TimeInterval = 10
    private let cache = PlatformUsageCache<PlatformUsageData>()

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = cache.read(timeout: cacheTimeout) {
            return cached
        }

        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(.deepseek)
        }

        guard !config.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(.deepseek)
        }

        let urlString = config.apiBaseURL.hasSuffix("/") ? config.apiBaseURL + "user/balance" : config.apiBaseURL + "/user/balance"
        guard let url = URL(string: urlString) else {
            throw PlatformError.invalidResponse(.deepseek)
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
            throw PlatformError.networkError(.deepseek, error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.invalidResponse(.deepseek)
        }

        if httpResponse.statusCode == 401 {
            throw PlatformError.unauthorized(.deepseek)
        }

        guard httpResponse.statusCode == 200 else {
            let responseString = String(data: data, encoding: .utf8) ?? "unable to decode"
            throw PlatformError.networkError(.deepseek, "HTTP \(httpResponse.statusCode): \(responseString.prefix(200))")
        }

        let balanceResponse: DeepSeekBalanceResponse
        do {
            balanceResponse = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            throw PlatformError.decodingError(.deepseek, error.localizedDescription)
        }

        var metrics: [UsageMetric] = []
        var totalBalance: Double = 0
        for info in balanceResponse.balanceInfos {
            let balance = Double(info.totalBalance) ?? 0
            totalBalance += balance
            metrics.append(UsageMetric(label: info.currency, currentValue: balance, totalValue: nil, unit: info.currency, resetTime: nil))
        }

        let isHealthy = balanceResponse.isAvailable && totalBalance > 0

        let usageData = PlatformUsageData(
            platform: .deepseek,
            displayName: "DeepSeek",
            metrics: metrics,
            lastUpdated: Date(),
            isHealthy: isHealthy
        )

        cache.write(usageData)
        return usageData
    }

    func clearCache() {
        cache.clear()
    }
}
