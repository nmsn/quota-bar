import Foundation

// MiMo tokenPlan/usage 接口返回结构.
// monthUsage: 本月用量; usage: 套餐总量 + 补偿额度.
struct MiMoUsageResponse: Codable {
    let code: Int
    let message: String?
    let data: MiMoUsageData?
}

struct MiMoUsageData: Codable {
    let monthUsage: MiMoUsageGroup?
    let usage: MiMoUsageGroup?
}

struct MiMoUsageGroup: Codable {
    let percent: Double?       // 整组已用百分比 (0-1)
    let items: [MiMoUsageItem]?
}

struct MiMoUsageItem: Codable {
    let name: String?          // month_total_token / plan_total_token / compensation_total_token
    let used: Double?
    let limit: Double?
    let percent: Double?       // 单项已用百分比 (0-1)
}

// MiMo tokenPlan/detail 接口返回结构.
// currentPeriodEnd: 当前套餐周期结束时间 (即到期/重置时间).
struct MiMoDetailResponse: Codable {
    let code: Int
    let message: String?
    let data: MiMoDetailData?
}

struct MiMoDetailData: Codable {
    let planCode: String?       // pro / max / lite ...
    let planName: String?       // Pro / Max ...
    let currentPeriodEnd: String?  // "2026-06-26 23:59:59"
    let expired: Bool?
}

final class MiMoPlatformAPIService: PlatformAPIService {
    let platformType: PlatformType = .mimo

    private let cacheTimeout: TimeInterval = 10
    private let cache = PlatformUsageCache<PlatformUsageData>()

    // MiMo 控制台用量接口的固定路径.
    // apiBaseURL 在配置里存的是 https://platform.xiaomimimo.com
    private let usagePath = "/api/v1/tokenPlan/usage"
    private let detailPath = "/api/v1/tokenPlan/detail"

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = cache.read(timeout: cacheTimeout) {
            return cached
        }

        // MiMo 用 Cookie 鉴权, Cookie 字符串当作 apiKey 存进来, authHeader="Cookie".
        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(config.platformType)
        }

        let baseURL = config.apiBaseURL
        guard !baseURL.isEmpty else {
            throw PlatformError.notConfigured(config.platformType)
        }

        // 并发请求 usage 和 detail 两个接口, 合并结果.
        async let usageRawTask = fetchEndpoint(baseURL + usagePath, config: config, network: network)
        async let detailRawTask = fetchEndpoint(baseURL + detailPath, config: config, network: network)

        let (usageRaw, detailRaw) = try await (usageRawTask, detailRawTask)

        // 解析 usage
        let usageResponse: MiMoUsageResponse
        do {
            usageResponse = try JSONDecoder().decode(MiMoUsageResponse.self, from: usageRaw)
        } catch {
            throw PlatformError.decodingError(config.platformType, error.localizedDescription)
        }
        // 业务码非 0 表示 Cookie 失效或账号异常
        if usageResponse.code != 0 {
            throw PlatformError.apiError(config.platformType, usageResponse.message ?? "code \(usageResponse.code)")
        }

        // 解析 detail (失败不致命, 到期时间可选)
        var planEnd: Date? = nil
        var planName: String? = nil
        if let detailResp = try? JSONDecoder().decode(MiMoDetailResponse.self, from: detailRaw),
           detailResp.code == 0 {
            planName = detailResp.data?.planName
            planEnd = parseDate(detailResp.data?.currentPeriodEnd)
        }

        // 组装 metrics
        var metrics: [UsageMetric] = []

        // 只显示套餐主额度 (plan_total_token). 这是你最关心的核心额度.
        // monthUsage (本月累计, 含补偿额度消耗) 和 compensation (补偿额度) 都不单独展示,
        // 因为你的用量先从补偿额度扣, 主额度才是套餐本体.
        if let items = usageResponse.data?.usage?.items {
            if let plan = items.first(where: { $0.name == "plan_total_token" }),
               let used = plan.used, let limit = plan.limit, limit > 0 {
                let remainingPct = max(0, (limit - used) / limit * 100)
                metrics.append(UsageMetric(
                    label: "monthly_usage",
                    currentValue: remainingPct,
                    totalValue: 100,
                    unit: "%",
                    resetTime: planEnd
                ))
            }
        }

        // 健康判断: 主额度剩余 >= 15% 视为正常
        let isHealthy: Bool
        if let items = usageResponse.data?.usage?.items,
           let plan = items.first(where: { $0.name == "plan_total_token" }),
           let used = plan.used, let limit = plan.limit, limit > 0 {
            let remainingPct = (limit - used) / limit * 100
            isHealthy = remainingPct >= 15
        } else {
            // metrics 为空时无法判断额度, 不报"偏低"假红 (UI 会显示灰色"无数据")
            isHealthy = true
        }

        let displayName = planName.map { "MiMo (\($0))" } ?? "MiMo"
        let usageData = PlatformUsageData(
            platform: config.platformType,
            displayName: displayName,
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

    // MARK: - Private

    // 发单个 GET 请求, 带 Cookie. 返回原始 Data.
    private func fetchEndpoint(_ urlString: String, config: PlatformConfigData, network: NetworkService) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw PlatformError.invalidResponse(config.platformType)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Cookie 鉴权: authHeader="Cookie", apiKey=完整cookie字符串
        request.setValue(config.apiKey, forHTTPHeaderField: config.authHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Asia/Shanghai", forHTTPHeaderField: "x-timezone")
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
        // 401/403 表示 Cookie 失效, 需要用户重新抓取
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw PlatformError.unauthorized(config.platformType)
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PlatformError.networkError(config.platformType, "HTTP \(httpResponse.statusCode): \(body.prefix(200))")
        }
        return data
    }

    // 解析 "2026-06-26 23:59:59" 这种格式. MiMo 用东八区时间.
    private func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Asia/Shanghai")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: s)
    }
}
