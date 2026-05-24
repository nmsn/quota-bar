# Add GLM Platform Support

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add GLM (智谱AI) as a new platform option with domestic/international region selection.

**Architecture:** Add `.glm` case to PlatformType, create GLMPlatformService, and include a region selector that switches between two API endpoints.

**Tech Stack:** Swift, SwiftUI, AppKit, UserDefaults

---

## GLM API Reference

Based on research:

| Region | API Endpoint | Auth |
|--------|--------------|------|
| **Domestic (国内)** | `https://open.bigmodel.cn/api/monitor/usage/quota/limit` | `Authorization: <API_TOKEN>` |
| **International (国际)** | `https://api.z.ai/api/monitor/usage/quota/limit` | `Authorization: <API_TOKEN>` |

- **No Bearer prefix** - auth_prefix should be empty string
- **Response Format**: JSON with `limits` array

```json
{
  "code": 200,
  "data": {
    "limits": [
      {"type": "TIME_LIMIT", "usage": 1000, "currentValue": 72, "remaining": 928},
      {"type": "TOKENS_LIMIT", "percentage": 44}
    ]
  }
}
```

---

## File Structure

```
Models/
  PlatformProtocol.swift           # Add: .glm case

Services/Platforms/
  GLMPlatform/
    GLMPlatformService.swift        # Create: GLM API implementation

Resources/
  ConfigTemplates/
    glm.template.json              # Create: GLM config template with region field
  en.json                          # Add: GLM i18n strings
  zh-Hans.json                     # Add: GLM i18n strings

Services/Platforms/
  PlatformManager.swift            # Register: GLMPlatformAPIService()
```

---

## Task 1: Add `.glm` to PlatformType Enum

**Files:**
- Modify: `Models/PlatformProtocol.swift`

- [ ] **Step 1: Add `.glm` case to PlatformType enum**

```swift
case glm
```

- [ ] **Step 2: Add GLM to displayName computed property**

```swift
case .glm: return "GLM"
```

---

## Task 2: Create GLM Config Template with Region Support

**Files:**
- Create: `Resources/ConfigTemplates/glm.template.json`

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

**Note:** The `region` field can be "domestic" or "international". The service will use `api_base_url` if region is "domestic", or `api_base_url_international` if region is "international".

---

## Task 3: Create GLM Platform Service

**Files:**
- Create: `Services/Platforms/GLMPlatform/GLMPlatformService.swift`

```swift
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
    let platformType: PlatformType = .glm

    private let cacheTimeout: TimeInterval = 10
    private var cache: (data: PlatformUsageData, timestamp: Date)?

    private func apiBaseURL(for config: PlatformConfigData) -> String {
        let region = config.region ?? "domestic"
        if region == "international" {
            return config.apiBaseURLInternational
        }
        return config.apiBaseURL
    }

    func fetchUsage(config: PlatformConfigData, network: NetworkService) async throws -> PlatformUsageData {
        if let cached = cache, Date().timeIntervalSince(cached.timestamp) < cacheTimeout {
            return cached.data
        }

        guard !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformError.notConfigured(.glm)
        }

        let baseURL = apiBaseURL(for: config)
        guard let url = URL(string: baseURL) else {
            throw PlatformError.invalidResponse(.glm)
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
            throw PlatformError.networkError(.glm, error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.invalidResponse(.glm)
        }

        if httpResponse.statusCode == 401 {
            throw PlatformError.unauthorized(.glm)
        }

        guard httpResponse.statusCode == 200 else {
            throw PlatformError.networkError(.glm, "HTTP \(httpResponse.statusCode)")
        }

        let usageResponse: GLMUsageResponse
        do {
            usageResponse = try JSONDecoder().decode(GLMUsageResponse.self, from: data)
        } catch {
            throw PlatformError.decodingError(.glm, error.localizedDescription)
        }

        var metrics: [UsageMetric] = []

        if let limits = usageResponse.data?.limits {
            for limit in limits {
                if limit.type == "TIME_LIMIT", let remaining = limit.remaining, let usage = limit.usage {
                    metrics.append(UsageMetric(
                        label: "Time Limit",
                        currentValue: Double(remaining),
                        totalValue: Double(usage),
                        unit: "times",
                        resetTime: nil
                    ))
                } else if limit.type == "TOKENS_LIMIT", let percentage = limit.percentage {
                    metrics.append(UsageMetric(
                        label: "Tokens Limit",
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
            platform: .glm,
            displayName: "GLM",
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
```

---

## Task 4: Update PlatformConfigData to Support Region

**Files:**
- Modify: `Services/Platforms/PlatformConfigStore.swift`

- [ ] **Add region property to PlatformConfigData struct**

```swift
var region: String?  // "domestic" or "international"
var apiBaseURLInternational: String?
```

---

## Task 5: Register GLM in PlatformManager

**Files:**
- Modify: `Services/Platforms/PlatformManager.swift`

Add in `init()`:

```swift
register(GLMPlatformAPIService())
```

---

## Task 6: Add i18n Strings

**Files:**
- Modify: `Resources/en.json`
- Modify: `Resources/zh-Hans.json`

Add entries:

```json
"platform.glm": "GLM"
```

---

## Task 7: Add Region Selector to Config UI

**Files:**
- Modify: `Views/PopoverContentView.swift` or wherever platform config is shown

- [ ] **Add region selector for GLM in config section**

The config section should show a region picker (Domestic/International) when configuring GLM.

---

## Task 8: Build and Test

- [ ] **Step 1: Generate project and build**

Expected: BUILD SUCCEEDED

---

## Plan complete

**Execution options:**

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task
2. **Inline Execution** - Execute tasks in this session
3. **Manual** - I implement directly

**Which approach?**