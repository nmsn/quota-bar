# AI Platform API Reference

> Reference document extracted from cc-switch project for implementing platform balance/quota APIs.

---

## Balance APIs (账户余额)

Return `UsageResult` with balance information for pay-as-you-go billing models.

| Platform | URL | Auth | Response Key | Unit |
|----------|-----|------|--------------|------|
| **DeepSeek** | `GET https://api.deepseek.com/user/balance` | `Bearer {api_key}` | `balance_infos[].total_balance` | Currency (CNY) |
| **StepFun** | `GET https://api.stepfun.com/v1/accounts` | `Bearer {api_key}` | `balance` | CNY |
| **SiliconFlow CN** | `GET https://api.siliconflow.cn/v1/user/info` | `Bearer {api_key}` | `data.totalBalance` | CNY |
| **SiliconFlow EN** | `GET https://api.siliconflow.com/v1/user/info` | `Bearer {api_key}` | `data.totalBalance` | USD |
| **OpenRouter** | `GET https://openrouter.ai/api/v1/credits` | `Bearer {api_key}` | `data.total_credits - data.total_usage` | USD |
| **Novita AI** | `GET https://api.novita.ai/v3/user/balance` | `Bearer {api_key}` | `availableBalance / 10000` | USD (unit: 0.0001) |

---

## Subscription/Quota APIs (套餐额度)

Return `SubscriptionQuota` with tiered usage data (5-hour window, weekly limit).

| Platform | URL | Auth | Tier Types | Notes |
|----------|-----|------|------------|-------|
| **Claude** | `GET https://api.anthropic.com/api/oauth/usage` | `Bearer {oauth_token}` | `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet` | OAuth-based, reads from Keychain |
| **Codex/ChatGPT** | `GET https://chatgpt.com/backend-api/wham/usage` | `Bearer {oauth_token}` | `18000s` → `five_hour`, `604800s` → `seven_day` | OAuth-based |
| **Gemini** | `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` + `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` | `Bearer {access_token}` | `gemini_pro`, `gemini_flash`, `gemini_flash_lite` | Two-step: get project ID first, then quota |
| **Kimi** | `GET https://api.kimi.com/coding/v1/usages` | `Bearer {api_key}` | `five_hour`, `weekly_limit` | From `limits[].detail` and `usage` |
| **GLM/智谱** | `GET https://api.z.ai/api/monitor/usage/quota/limit` | `{api_key}` (no Bearer) | `five_hour`, `weekly_limit` | From `limits[].TOKENS_LIMIT.percentage`, sorted by `nextResetTime` |
| **MiniMax CN** | `GET https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains` | `Bearer {api_key}` | `five_hour`, `weekly_limit` | From `model_remains[0]` |
| **MiniMax EN** | `GET https://api.minimax.io/v1/api/openplatform/coding_plan/remains` | `Bearer {api_key}` | `five_hour`, `weekly_limit` | Same response format as CN |

---

## Response Formats

### DeepSeek Balance Response
```json
{
  "is_available": true,
  "balance_infos": [
    { "currency": "CNY", "total_balance": "100.00", "granted_balance": "50.00", "topped_up_balance": "50.00" }
  ]
}
```

### GLM Coding Plan Response
```json
{
  "code": 200,
  "success": true,
  "data": {
    "limits": [
      { "type": "TIME_LIMIT", "remaining": 928, "usage": 1000, "currentValue": 72 },
      { "type": "TOKENS_LIMIT", "percentage": 44, "nextResetTime": 174... }
    ],
    "level": "pro"
  }
}
```

### Kimi Coding Plan Response
```json
{
  "limits": [
    { "detail": { "limit": 1000, "remaining": 500, "resetTime": "2026-05-24T12:00:00Z" } }
  ],
  "usage": { "limit": 5000, "remaining": 3000, "resetTime": "2026-05-30T00:00:00Z" }
}
```

### MiniMax Coding Plan Response
```json
{
  "base_resp": { "status_code": 0, "status_msg": "success" },
  "model_remains": [{
    "current_interval_total_count": 1000,
    "current_interval_usage_count": 200,
    "end_time": 174...,
    "current_weekly_total_count": 5000,
    "current_weekly_usage_count": 1000,
    "weekly_end_time": 174...
  }]
}
```

---

## Tier Naming Convention

| Tier Name | Time Window | Description |
|-----------|-------------|-------------|
| `five_hour` | 5 hours | Short-term usage window |
| `seven_day` | 7 days | Weekly usage window |
| `weekly_limit` | 7 days | Alternative weekly tier name |
| `gemini_pro` | - | Gemini Pro model quota |
| `gemini_flash` | - | Gemini Flash model quota |
| `gemini_flash_lite` | - | Gemini Flash Lite model quota |

---

## UsageData Structure (for Balance APIs)

```swift
struct UsageData {
    plan_name: Option<String>,      // Display name (e.g., "CNY", "USD")
    remaining: Option<f64>,         // Remaining balance/credits
    total: Option<f64>,             // Total allowance (if available)
    used: Option<f64>,              // Used amount (if available)
    unit: Option<String>,           // Currency unit
    is_valid: Option<bool>,        // Validity flag
    invalid_message: Option<String>, // Error message if invalid
    extra: Option<serde_json::Value> // Additional data
}
```

---

## Provider Detection Patterns

### Balance Providers
```
DeepSeek      → contains("api.deepseek.com")
StepFun      → contains("api.stepfun.ai") || contains("api.stepfun.com")
SiliconFlow CN → contains("api.siliconflow.cn")
SiliconFlow EN → contains("api.siliconflow.com")
OpenRouter   → contains("openrouter.ai")
NovitaAI     → contains("api.novita.ai")
```

### Coding Plan Providers
```
Kimi         → contains("api.kimi.com/coding")
GLM CN       → contains("open.bigmodel.cn") || contains("bigmodel.cn")
GLM EN       → contains("api.z.ai")
MiniMax CN   → contains("api.minimaxi.com")
MiniMax EN   → contains("api.minimax.io")
```

---

## Notes

1. **Auth Header Variations**:
   - Most platforms use `Authorization: Bearer {api_key}`
   - GLM uses `Authorization: {api_key}` (no Bearer prefix)

2. **Token Refresh**:
   - Gemini access tokens expire in ~1 hour, require refresh using `refresh_token`
   - Claude/Codex tokens stored in macOS Keychain

3. **Unit Conversions**:
   - Novita AI: amounts are in 0.0001 USD units, divide by 10000 to get USD

4. **Time Format**:
   - Timestamps may be in seconds or milliseconds (milliseconds > 1e12)
   - ISO 8601 format used for reset times