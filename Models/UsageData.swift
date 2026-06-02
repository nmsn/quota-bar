import Foundation

struct UsageData {
    let modelName: String
    let dailyRemaining: Int
    let dailyTotal: Int
    let dailyPercentage: Double
    let dailyResetTime: String
    let dailyResetMs: Int
    let weeklyRemaining: Int
    let weeklyTotal: Int
    let weeklyPercentage: Double
    let weeklyResetTime: String
    let weeklyResetMs: Int
    let expiryDate: Date?
    let isHealthy: Bool

    var dailyUsedPercentage: Double {
        guard dailyTotal > 0 else { return 0 }
        return Double(dailyTotal - dailyRemaining) / Double(dailyTotal)
    }

    var weeklyUsedPercentage: Double {
        guard weeklyTotal > 0 else { return 0 }
        return Double(weeklyTotal - weeklyRemaining) / Double(weeklyTotal)
    }

    var statusColor: String {
        let maxPercentage = max(dailyUsedPercentage, weeklyUsedPercentage)
        if maxPercentage >= 0.85 {
            return "red"
        } else if maxPercentage >= 0.60 {
            return "yellow"
        } else {
            return "green"
        }
    }

    var dailyResetFormatted: String {
        let hours = dailyResetMs / (1000 * 60 * 60)
        let minutes = (dailyResetMs % (1000 * 60 * 60)) / (1000 * 60)
        if hours > 0 {
            let template = I18nService.shared.translate("daily.reset.remaining")
            return String(format: template, hours, minutes)
        } else {
            return I18nService.shared.translate("daily.reset.minutesonly")
        }
    }

    var weeklyResetFormatted: String {
        if weeklyResetMs == 0 {
            return I18nService.shared.translate("daily.reset.soon")
        }
        let days = weeklyResetMs / (1000 * 60 * 60 * 24)
        let hours = (weeklyResetMs % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)
        if days > 0 {
            let template = I18nService.shared.translate("weekly.reset.remaining")
            return String(format: template, days, hours)
        } else {
            let template = I18nService.shared.translate("weekly.reset.hours")
            return String(format: template, hours)
        }
    }

    var statusText: String {
        switch statusColor {
        case "red": return "⚠️ " + I18nService.shared.translate("status.critical")
        case "yellow": return "⚡ " + I18nService.shared.translate("status.warning")
        default: return "✓ " + I18nService.shared.translate("status.healthy")
        }
    }
}

struct APIResponse: Codable {
    let baseResp: BaseResp?
    let modelRemains: [ModelRemain]?

    enum CodingKeys: String, CodingKey {
        case baseResp = "base_resp"
        case modelRemains = "model_remains"
    }
}

/// MiniMax 顶层响应里的 base_resp 字段, 非 0 表示 API 业务错误
struct BaseResp: Codable {
    let statusCode: Int
    let statusMsg: String?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}

struct ModelRemain: Codable {
    let modelName: String?
    let endTime: Int?
    let weeklyEndTime: Int?
    let remainsTime: Int?
    let weeklyRemainsTime: Int?
    let currentIntervalRemainingPercent: Double?
    let currentWeeklyRemainingPercent: Double?
    /// 周限额是否激活: 1 = 激活, 其它值(包括 nil) = 该 plan 无周限额
    let currentWeeklyStatus: Int?

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case endTime = "end_time"
        case weeklyEndTime = "weekly_end_time"
        case remainsTime = "remains_time"
        case weeklyRemainsTime = "weekly_remains_time"
        case currentIntervalRemainingPercent = "current_interval_remaining_percent"
        case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
        case currentWeeklyStatus = "current_weekly_status"
    }
}