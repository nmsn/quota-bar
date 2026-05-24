# Platform API Enhancement Plan

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance MiniMax (add EN endpoint), GLM (add CN endpoint, fix tier naming), and implement Kimi platform service based on API reference document.

**Architecture:** Extend existing platform services with region-based API URL selection. Follow existing PlatformAPIService protocol pattern. Each platform gets its own service file under `Services/Platforms/{Platform}Platform/`.

**Tech Stack:** Swift, SwiftUI, AppKit, UserDefaults

---

## File Structure

```
Services/Platforms/
  MiniMaxPlatform/
    MiniMaxPlatformService.swift    # Modify: add EN endpoint detection
  GLMPlatform/
    GLMPlatformService.swift        # Modify: add CN endpoint, fix tier naming
  KimiPlatform/                     # Create: new directory
    KimiPlatformService.swift       # Create: Kimi API implementation

Services/Platforms/
  PlatformConfigStore.swift         # Modify: add apiBaseURLInternational for Kimi

Services/Platforms/
  PlatformManager.swift             # Modify: register KimiPlatformService

Models/
  PlatformProtocol.swift            # Modify: add .kimi case

Resources/ConfigTemplates/
  kimi.template.json                # Create: Kimi config template

Resources/
  en.json                           # Modify: add Kimi i18n
  zh-Hans.json                      # Modify: add Kimi i18n

docs/
  platform-api-reference.md         # Reference: API specs already documented
```

---

## Task 1: Add `.kimi` to PlatformType Enum

**Files:**
- Modify: `Models/PlatformProtocol.swift`

- [ ] **Step 1: Add `.kimi` case to PlatformType enum**

```swift
case kimi
```

- [ ] **Step 2: Add Kimi to displayName computed property**

```swift
case .kimi: return "Kimi"
```

---

## Task 2: Create Kimi Config Template

**Files:**
- Create: `Resources/ConfigTemplates/kimi.template.json`

```json
{
  "api_base_url": "https://api.kimi.com/coding/v1/usages",
  "auth_header": "Authorization",
  "auth_prefix": "Bearer ",
  "api_key": "",
  "region": "domestic"
}
```

---

## Task 3: Create Kimi Platform Service

**Files:**
- Create: `Services/Platforms/KimiPlatform/KimiPlatformService.swift`

```swift
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
                    let used = (limitValue - remaining).max(0)
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
            let used = (limitValue - remaining).max(0)
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
```

---

## Task 4: Register Kimi in PlatformManager

**Files:**
- Modify: `Services/Platforms/PlatformManager.swift`

Add in `init()`:

```swift
register(KimiPlatformAPIService())
```

---

## Task 5: Add i18n Strings for Kimi

**Files:**
- Modify: `Resources/en.json`
- Modify: `Resources/zh-Hans.json`

Add entries:

```json
"platform.kimi": "Kimi"
```

---

## Task 6: Enhance MiniMax with EN Endpoint Support

**Files:**
- Modify: `Services/Platforms/MiniMaxPlatform/MiniMaxPlatformService.swift`

- [ ] **Step 1: Update apiBaseURL detection to support both CN and EN**

Replace the current `guard let url = URL(string: config.apiBaseURL)` section with:

```swift
private func apiBaseURL(for config: PlatformConfigData) -> String {
    let region = config.region ?? "domestic"
    if region == "international" {
        return config.apiBaseURLInternational ?? config.apiBaseURL
    }
    return config.apiBaseURL
}
```

Update `fetchUsage` to use `apiBaseURL(for:)` instead of directly using `config.apiBaseURL`.

- [ ] **Step 2: Fix tier labels**

Change metrics labels from "Daily"/"Weekly" to "five_hour"/"weekly_limit":

```swift
UsageMetric(label: "five_hour", currentValue: dailyUsed, totalValue: dailyTotal, unit: "requests", resetTime: dailyResetTime),
UsageMetric(label: "weekly_limit", currentValue: weeklyUsed, totalValue: weeklyTotal, unit: "requests", resetTime: weeklyResetTime)
```

---

## Task 7: Enhance GLM with CN Endpoint and Fix Tier Naming

**Files:**
- Modify: `Services/Platforms/GLMPlatform/GLMPlatformService.swift`

- [ ] **Step 1: Update apiBaseURL detection to support CN and EN**

```swift
private func apiBaseURL(for config: PlatformConfigData) -> String {
    let region = config.region ?? "domestic"
    if region == "international" {
        return config.apiBaseURLInternational ?? config.apiBaseURL
    }
    return config.apiBaseURL
}
```

Update `fetchUsage` to use `apiBaseURL(for:)` instead of directly using `config.apiBaseURL`.

- [ ] **Step 2: Fix tier labels**

Change from "Time Limit"/"Tokens Limit" to "five_hour"/"weekly_limit":

```swift
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
```

---

## Task 8: Update GLM Config Template with CN Endpoint

**Files:**
- Modify: `Resources/ConfigTemplates/glm.template.json`

Update to include both endpoints:

```json
{
  "api_base_url": "https://open.bigmodel.cn/api/monitor/usage/quota/limit",
  "api_base_url_international": "https://api.z.ai/api/monitor/usage/quota/limit",
  "auth_header": "Authorization",
  "auth_prefix": "",
  "api_key": "",
  "region": "domestic"
}
```

---

## Task 9: Update MiniMax Config Template with EN Endpoint

**Files:**
- Modify: `Resources/ConfigTemplates/minimax.template.json`

Update to include both endpoints:

```json
{
  "api_base_url": "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains",
  "api_base_url_international": "https://api.minimax.io/v1/api/openplatform/coding_plan/remains",
  "auth_header": "Authorization",
  "auth_prefix": "Bearer ",
  "api_key": "",
  "region": "domestic"
}
```

---

## Task 10: Build and Test

- [ ] **Step 1: Generate project and build**

Run: `xcodegen generate && xcodebuild -project quota-bar.xcodeproj -scheme quota-bar -configuration Debug build`
Expected: BUILD SUCCEEDED

---

## Plan complete and saved to `docs/superpowers/plans/2026-05-24-platform-api-enhancement.md`

**Two execution options:**

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**