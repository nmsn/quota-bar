import Foundation

// StepFun QueryStepPlanRateLimit 接口返回结构.
// five_hour_usage_left_rate / weekly_usage_left_rate: 剩余比例 (0-1)
// reset_time: Unix 时间戳, 可能是字符串或数字.
struct StepFunRateLimitResponse: Codable {
    let status: Int?
    let code: Int?
    let desc: String?
    let message: String?
    let fiveHourUsageLeftRate: FlexibleNumber?
    let weeklyUsageLeftRate: FlexibleNumber?
    let fiveHourUsageResetTime: FlexibleTimestamp?
    let weeklyUsageResetTime: FlexibleTimestamp?

    enum CodingKeys: String, CodingKey {
        case status, code, desc, message
        case fiveHourUsageLeftRate = "five_hour_usage_left_rate"
        case weeklyUsageLeftRate = "weekly_usage_left_rate"
        case fiveHourUsageResetTime = "five_hour_usage_reset_time"
        case weeklyUsageResetTime = "weekly_usage_reset_time"
    }

    var isSuccess: Bool { status == 1 }
}

// GetStepPlanStatus 接口返回: 拿套餐名
struct StepFunPlanStatusResponse: Codable {
    let status: Int?
    let subscription: Subscription?

    struct Subscription: Codable {
        let name: String?
    }

    var planName: String? {
        subscription?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// 灵活数字: JSON 里可能是 1 (int) 或 0.974 (double)
struct FlexibleNumber: Codable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = Double(i) }
        else if let d = try? c.decode(Double.self) { value = d }
        else { value = 0 }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

// 灵活时间戳: JSON 里可能是 "1781478000" (字符串) 或 1781478000 (数字)
struct FlexibleTimestamp: Codable {
    let value: Int64
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), let i = Int64(s) { value = i }
        else if let i = try? c.decode(Int64.self) { value = i }
        else if let i = try? c.decode(Int.self) { value = Int64(i) }
        else { value = 0 }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

// Passport 登录相关接口的通用返回 (accessToken/refreshToken 都是 {raw: "..."})
struct StepFunTokenResponse: Codable {
    let accessToken: TokenPair?
    let refreshToken: TokenPair?
    struct TokenPair: Codable { let raw: String }
}

// StepFun 平台 service.
//
// 鉴权方式: 账号密码登录. apiKey 字段存 "手机号\n密码" (换行分隔).
// StepFun 的 access token 30 分钟过期, 且 RefreshToken 接口换出来的是
// 匿名设备 token (mode 1), 无法访问需要登录态 (mode 2) 的用量接口.
// 所以本 service 采用: 登录拿到 token → 缓存 → 过期就重新登录.
final class StepFunPlatformAPIService: PlatformAPIService {
    let platformType: PlatformType = .stepfun

    private let cacheTimeout: TimeInterval = 30
    private let usageCache = PlatformUsageCache<PlatformUsageData>()

    // 登录后的 token 缓存 (进程内). access token 30 分钟过期.
    // tokenCache 带独立过期时间, 用 lock 保护并发访问.
    private var tokenCache: (token: String, expiry: Date)?
    private let tokenCacheLock = NSLock()

    // StepFun 控制台固定常量 (和 CodexBar 一致, webid 全程必须一致).
    // webid 同时也是 RegisterDevice 返回的 deviceID.
    private let webID = "c8a1002d2c457e758785a9979832217c7c0b884c"
    private let appID = "10300"
    private let host = "https://platform.stepfun.com"
    private let rateLimitPath = "/api/step.openapi.devcenter.Dashboard/QueryStepPlanRateLimit"
    private let planStatusPath = "/api/step.openapi.devcenter.Dashboard/GetStepPlanStatus"
    private let registerDevicePath = "/passport/proto.api.passport.v1.PassportService/RegisterDevice"
    private let signInPath = "/passport/proto.api.passport.v1.PassportService/SignInByPassword"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = usageCache.read(timeout: cacheTimeout) {
            return cached
        }

        // apiKey 存的是 "手机号\n密码". 解析出来.
        let (username, password) = parseCredentials(config.apiKey)
        guard !username.isEmpty, !password.isEmpty else {
            throw PlatformError.notConfigured(config.platformType)
        }

        // 用缓存的 token 试一次; 过期就重新登录.
        // 登录是 3 步 HTTP (ingress → register → signin), 失败要能重试.
        var token: String? = cachedToken()
        var lastError: Error?
        // 最多 3 轮, 给登录偶发失败 (网络抖动/服务端波动) 留重试机会.
        // 之前 login 失败直接 throw, 导致 app 长跑时偶尔失灵, 要等下次定时刷新才恢复.
        for attempt in 0..<3 {
            if token == nil {
                do {
                    token = try await login(username: username, password: password, network: network)
                } catch {
                    lastError = error
                    // 最后一次失败才抛出; 中间失败退避 2s 后重试
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    throw error
                }
            }
            guard let currentToken = token else { break }

            do {
                let result = try await queryWithToken(currentToken, network: network)
                usageCache.write(result)
                return result
            } catch PlatformError.unauthorized {
                // token 过期或失效, 清掉缓存重新登录
                clearTokenCache()
                token = nil
                lastError = PlatformError.unauthorized(platformType)
                continue
            } catch {
                throw error
            }
        }
        throw lastError ?? PlatformError.invalidResponse(config.platformType)
    }

    func clearCache() {
        usageCache.clear()
        clearTokenCache()
    }

    private func clearTokenCache() {
        tokenCacheLock.lock()
        defer { tokenCacheLock.unlock() }
        tokenCache = nil
    }

    // MARK: - Private

    // 解析 "手机号\n密码". 只用换行分隔 (不兼容冒号, 因为密码可能含冒号).
    private func parseCredentials(_ raw: String) -> (username: String, password: String) {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return ("", "") }
        // 第一行是用户名, 剩余全部视为密码 (密码本身可能含换行的情况不存在, 但防御性处理)
        let username = parts[0]
        let password = parts.dropFirst().joined(separator: "\n")
        return (username, password)
    }

    private func cachedToken() -> String? {
        tokenCacheLock.lock()
        defer { tokenCacheLock.unlock() }
        guard let cache = tokenCache, cache.expiry > Date() else { return nil }
        return cache.token
    }

    // 完整登录流程: 拿 INGRESSCOOKIE → RegisterDevice → SignInByPassword.
    // 返回组合 token "accessToken...refreshToken".
    private func login(username: String, password: String, network: NetworkService) async throws -> String {
        // Step 1: 拿 INGRESSCOOKIE (访问首页, 从 Set-Cookie 提取)
        let ingress = try await fetchIngressCookie(network: network)

        // Step 2: RegisterDevice → 匿名 token (组合格式)
        let anonCombined = try await registerDevice(ingress: ingress, network: network)

        // Step 3: SignInByPassword → 登录态 token (mode 2)
        let combined = try await signInByPassword(
            username: username, password: password,
            ingress: ingress, anonToken: anonCombined, network: network)

        // access token 30 分钟有效, 留 2 分钟余量提前过期
        tokenCacheLock.lock()
        tokenCache = (combined, Date().addingTimeInterval(28 * 60))
        tokenCacheLock.unlock()
        return combined
    }

    private func fetchIngressCookie(network: NetworkService) async throws -> String {
        guard let url = URL(string: host) else {
            throw PlatformError.invalidResponse(platformType)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "user-agent")
        request.timeoutInterval = 15

        let (data, response) = try await network.data(from: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlatformError.invalidResponse(platformType)
        }
        guard http.statusCode == 200 || http.statusCode == 302 else {
            throw PlatformError.networkError(platformType, "ingress HTTP \(http.statusCode)")
        }

        // 从 Set-Cookie 提取 INGRESSCOOKIE
        if let cookie = http.value(forHTTPHeaderField: "Set-Cookie"),
           let extracted = extractCookieValue(cookie, name: "INGRESSCOOKIE") {
            return extracted
        }
        // 遍历所有 Set-Cookie (有些服务器会返回多个)
        for (_, value) in http.allHeaderFields {
            if let str = value as? String,
               let extracted = extractCookieValue(str, name: "INGRESSCOOKIE") {
                return extracted
            }
        }
        _ = data  // body 不需要
        throw PlatformError.networkError(platformType, "no INGRESSCOOKIE in response")
    }

    private func registerDevice(ingress: String, network: NetworkService) async throws -> String {
        let body = try await postPassport(registerDevicePath, cookie: "INGRESSCOOKIE=\(ingress)",
                                           body: "{}", network: network)
        return try parseCombinedToken(body)
    }

    private func signInByPassword(username: String, password: String, ingress: String,
                                  anonToken: String, network: NetworkService) async throws -> String {
        let cookie = "Oasis-Token=\(anonToken); Oasis-Webid=\(webID); INGRESSCOOKIE=\(ingress)"
        let payload = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let body = try await postPassport(signInPath, cookie: cookie, body: payload, network: network)
        return try parseCombinedToken(body)
    }

    // 调 Passport 系列接口 (POST, 带 oasis-* headers)
    private func postPassport(_ path: String, cookie: String, body: Any, network: NetworkService) async throws -> Data {
        guard let url = URL(string: host + path) else {
            throw PlatformError.invalidResponse(platformType)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let bodyStr = body as? String {
            request.httpBody = Data(bodyStr.utf8)
        } else if let bodyData = body as? Data {
            request.httpBody = bodyData
        }
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(appID, forHTTPHeaderField: "oasis-appid")
        request.setValue("web", forHTTPHeaderField: "oasis-platform")
        request.setValue(webID, forHTTPHeaderField: "oasis-webid")
        request.setValue(userAgent, forHTTPHeaderField: "user-agent")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15

        return try await sendAndValidate(request, network: network)
    }

    // 组合 token: "accessToken...refreshToken"
    private func parseCombinedToken(_ data: Data) throws -> String {
        let resp: StepFunTokenResponse
        do {
            resp = try JSONDecoder().decode(StepFunTokenResponse.self, from: data)
        } catch {
            throw PlatformError.decodingError(platformType, error.localizedDescription)
        }
        guard let access = resp.accessToken?.raw, !access.isEmpty else {
            throw PlatformError.unauthorized(platformType)
        }
        if let refresh = resp.refreshToken?.raw, !refresh.isEmpty {
            return "\(access)...\(refresh)"
        }
        return access
    }

    // MARK: - Query usage

    private func queryWithToken(_ token: String, network: NetworkService) async throws -> PlatformUsageData {
        // 并发请求用量 + 套餐状态
        async let rateRaw = postDashboard(rateLimitPath, token: token, network: network)
        async let planRaw = postDashboard(planStatusPath, token: token, network: network)

        let (rateData, planData) = try await (rateRaw, planRaw)

        // 解析用量
        let rateResp: StepFunRateLimitResponse
        do {
            rateResp = try JSONDecoder().decode(StepFunRateLimitResponse.self, from: rateData)
        } catch {
            throw PlatformError.decodingError(platformType, error.localizedDescription)
        }
        guard rateResp.isSuccess else {
            let msg = rateResp.desc ?? rateResp.message ?? "code \(rateResp.code ?? -1)"
            throw PlatformError.apiError(platformType, msg)
        }

        // 解析套餐名 (失败不致命)
        var planName: String? = nil
        if let plan = try? JSONDecoder().decode(StepFunPlanStatusResponse.self, from: planData),
           plan.status == 1 {
            planName = plan.planName
        }

        // 组装 metrics: 5小时窗口 (主) + 每周窗口 (副)
        var metrics: [UsageMetric] = []

        if let fiveRate = rateResp.fiveHourUsageLeftRate?.value,
           let fiveReset = rateResp.fiveHourUsageResetTime?.value {
            let remainingPct = max(0, min(100, fiveRate * 100))
            metrics.append(UsageMetric(
                label: "five_hour",
                currentValue: remainingPct,
                totalValue: 100,
                unit: "%",
                resetTime: Date(timeIntervalSince1970: TimeInterval(fiveReset))
            ))
        }

        if let weeklyRate = rateResp.weeklyUsageLeftRate?.value,
           let weeklyReset = rateResp.weeklyUsageResetTime?.value {
            let remainingPct = max(0, min(100, weeklyRate * 100))
            metrics.append(UsageMetric(
                label: "weekly_limit",
                currentValue: remainingPct,
                totalValue: 100,
                unit: "%",
                resetTime: Date(timeIntervalSince1970: TimeInterval(weeklyReset))
            ))
        }

        guard !metrics.isEmpty else {
            throw PlatformError.decodingError(platformType, "Missing rate limit fields")
        }

        // 健康判断: 5小时窗口剩余 >= 15% 视为正常
        let fiveRemaining = rateResp.fiveHourUsageLeftRate?.value
        let isHealthy = fiveRemaining.map { $0 * 100 >= 15 } ?? !metrics.isEmpty

        let displayName = planName.map { "StepFun (\($0))" } ?? "StepFun"
        return PlatformUsageData(
            platform: platformType,
            displayName: displayName,
            metrics: metrics,
            lastUpdated: Date(),
            isHealthy: isHealthy
        )
    }

    // 调 Dashboard 系列接口 (POST, 组合 token 放 Cookie)
    private func postDashboard(_ path: String, token: String, network: NetworkService) async throws -> Data {
        guard let url = URL(string: host + path) else {
            throw PlatformError.invalidResponse(platformType)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(appID, forHTTPHeaderField: "oasis-appid")
        request.setValue("web", forHTTPHeaderField: "oasis-platform")
        request.setValue(webID, forHTTPHeaderField: "oasis-webid")
        request.setValue(userAgent, forHTTPHeaderField: "user-agent")
        request.setValue("Oasis-Token=\(token); Oasis-Webid=\(webID)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15

        return try await sendAndValidate(request, network: network)
    }

    // MARK: - HTTP helpers

    private func sendAndValidate(_ request: URLRequest, network: NetworkService) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await network.data(from: request)
        } catch {
            throw PlatformError.networkError(platformType, error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PlatformError.invalidResponse(platformType)
        }
        // 401/403: token 过期或未登录
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PlatformError.unauthorized(platformType)
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PlatformError.networkError(platformType, "HTTP \(http.statusCode): \(body.prefix(200))")
        }
        // 业务层鉴权失败 (HTTP 200 但 body 含 unauthenticated)
        if let body = String(data: data, encoding: .utf8),
           body.contains("\"unauthenticated\"") {
            throw PlatformError.unauthorized(platformType)
        }
        return data
    }

    // 从 Set-Cookie 字符串里提取指定 cookie 的值
    private func extractCookieValue(_ setCookie: String, name: String) -> String? {
        guard setCookie.contains("\(name)=") else { return nil }
        let parts = setCookie.components(separatedBy: "\(name)=")
        guard parts.count > 1 else { return nil }
        return parts[1].components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespaces)
    }
}
