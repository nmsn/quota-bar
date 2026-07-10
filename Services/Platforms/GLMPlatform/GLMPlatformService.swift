import Foundation

// 智谱 quota/limit 接口返回的单条限额信息.
// type 区分大类别: TOKENS_LIMIT = Token 额度(再按 unit 区分 5小时/周),
//                  TIME_LIMIT = MCP 月度调用次数额度.
// unit 仅对 TOKENS_LIMIT 有意义: 3 = 5小时窗口, 6 = 每周.
struct GLMLimitInfo: Codable {
    let type: String
    let unit: Int?          // Token 额度的窗口单位: 3=5小时, 6=每周
    let percentage: Int?    // 已用百分比 (0-100)
    let usage: Int?         // 总额度 (TIME_LIMIT 的总次数, 如 1000)
    let currentValue: Int?  // 已用次数 (TIME_LIMIT 用)
    let remaining: Int?     // 剩余次数 (TIME_LIMIT 用)
    let nextResetTime: Int64?  // 重置时间, 毫秒时间戳
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
    private let cache = PlatformUsageCache<PlatformUsageData>()

    private func apiBaseURL(for config: PlatformConfigData) -> String {
        let region = config.region ?? "domestic"
        if region == "international" {
            return config.apiBaseURLInternational ?? config.apiBaseURL
        }
        return config.apiBaseURL
    }

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = cache.read(timeout: cacheTimeout) {
            return cached
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

        // 业务码错误 (key 失效 / 账户异常): success=false 时透出 msg,
        // 不要静默走空 metrics 让用户看到"无数据/红"却不知原因.
        if !usageResponse.success {
            let msg = usageResponse.msg.isEmpty ? "GLM request failed" : usageResponse.msg
            throw PlatformError.apiError(config.platformType, msg)
        }

        var metrics: [UsageMetric] = []

        if let limits = usageResponse.data?.limits {
            for limit in limits {
                if limit.type == "TOKENS_LIMIT" {
                    // Token 额度, 按 unit 区分窗口: 3 = 5小时, 6 = 每周.
                    // 已用百分比 percentage → 剩余 = 100 - percentage.
                    let usedPct = limit.percentage ?? 0
                    let remainingPct = max(0, 100 - usedPct)
                    let label = (limit.unit == 6) ? "weekly_limit" : "five_hour"
                    let resetTime = resetDate(from: limit.nextResetTime)
                    metrics.append(UsageMetric(
                        label: label,
                        currentValue: Double(remainingPct),
                        totalValue: 100,
                        unit: "%",
                        resetTime: resetTime
                    ))
                } else if limit.type == "TIME_LIMIT" {
                    // TIME_LIMIT = MCP 月度调用次数额度.
                    // 按次数显示: 剩余/总次数 (如 932/1000 次).
                    // percentage 是已用百分比, 用它判断是否健康.
                    let remaining = limit.remaining ?? 0
                    let total = limit.usage ?? 0
                    let resetTime = resetDate(from: limit.nextResetTime)
                    metrics.append(UsageMetric(
                        label: "mcp_monthly",
                        currentValue: Double(remaining),
                        totalValue: Double(total),
                        unit: "times",
                        resetTime: resetTime
                    ))
                }
            }
        }

        // 固定排序: 5 小时 → 周限额 → MCP 月度, 保证主要指标始终在前.
        let order: [String: Int] = ["five_hour": 0, "weekly_limit": 1, "mcp_monthly": 2]
        metrics.sort { (order[$0.label] ?? 99) < (order[$1.label] ?? 99) }

        // 5 小时和周限额有各自的剩余百分比, MCP 月度按次数判断.
        // 只要任一一项剩余 < 15% 视为偏低. (unit=="%" 和次数型逻辑相同, 合并)
        let isHealthy = usageResponse.success && !metrics.isEmpty && metrics.allSatisfy { metric in
            guard let total = metric.totalValue, total > 0 else { return true }
            return metric.currentValue / total * 100 >= 15
        }

        let usageData = PlatformUsageData(
            platform: config.platformType,
            displayName: config.platformType.displayName,
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

    // 智谱接口的 nextResetTime 是毫秒级时间戳, 转成 Date 给 UI 显示倒计时.
    // 无效或缺失时返回 nil.
    private func resetDate(from ms: Int64?) -> Date? {
        guard let ms, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
    }
}