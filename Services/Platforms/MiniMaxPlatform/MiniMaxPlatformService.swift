import Foundation

final class MiniMaxPlatformAPIService: PlatformAPIService {
    let platformType: PlatformType = .minimax_cn

    private let cacheTimeout: TimeInterval = 10
    private let cache = PlatformUsageCache<PlatformUsageData>()

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = cache.read(timeout: cacheTimeout) {
            return cached
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

        // 检查 API 业务状态码 (base_resp.status_code). 非 0 表示账户欠费、key 失效、
        // plan 暂停等业务错误, 此时直接给用户看 status_msg, 比笼统的"无效响应"更有用.
        if let baseResp = apiResponse.baseResp, baseResp.statusCode != 0 {
            let message = baseResp.statusMsg?.isEmpty == false
                ? baseResp.statusMsg!
                : "status_code \(baseResp.statusCode)"
            throw PlatformError.apiError(config.platformType, message)
        }

        // 找不到 model_name == "general" 时回退到第一个 item, 而不是直接报错.
        // 跟上游 cc-switch 行为对齐, 防止 API 微调 model_name 时整个 panel 直接挂掉.
        guard let modelRemains = apiResponse.modelRemains, !modelRemains.isEmpty else {
            throw PlatformError.invalidResponse(config.platformType)
        }
        let modelData = modelRemains.first(where: { $0.modelName == "general" }) ?? modelRemains[0]

        let usageData = parseUsageData(from: modelData, platform: config.platformType)
        cache.write(usageData)
        return usageData
    }

    func clearCache() {
        cache.clear()
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

        // 剩余 >= 15% 视为健康 (UI 显示"正常" + 绿色), 低于 15% 触发"偏低"红色提示
        let isHealthy = dailyRemainingPct >= 15.0

        // 5 小时窗口永远存在
        var metrics: [UsageMetric] = [
            UsageMetric(label: "five_hour", currentValue: dailyRemainingPct, totalValue: 100, unit: "%", resetTime: dailyResetTime)
        ]

        // 周限额仅在 current_weekly_status == 1 时展示. 其它值(包括 nil)表示该 plan
        // 无周限额 — 跟上游 cc-switch 的语义对齐, 避免展示过时的/随机的 weekly 数据.
        if model.currentWeeklyStatus == 1 {
            // 周额度加成 (weekly_boost_permille > 1000 表示有加成, 如 1500 = 150%):
            // 区分"标准 100%"和"加成 150%"两种 plan, 用不同 label 让 UI 显示对应类型.
            let boosted = (model.weeklyBoostPermille ?? 0) > 1000
            metrics.append(
                UsageMetric(label: boosted ? "weekly_limit_boosted" : "weekly_limit", currentValue: weeklyRemainingPct, totalValue: 100, unit: "%", resetTime: weeklyResetTime)
            )
        }

        return PlatformUsageData(
            platform: platform,
            displayName: platform.displayName,
            metrics: metrics,
            lastUpdated: Date(),
            isHealthy: isHealthy
        )
    }
}
