import Foundation

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
    /// 周额度加成 (千分比): 1500 = 150% 加成, 0/nil = 标准 100% 额度
    let weeklyBoostPermille: Int?

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case endTime = "end_time"
        case weeklyEndTime = "weekly_end_time"
        case remainsTime = "remains_time"
        case weeklyRemainsTime = "weekly_remains_time"
        case currentIntervalRemainingPercent = "current_interval_remaining_percent"
        case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
        case currentWeeklyStatus = "current_weekly_status"
        case weeklyBoostPermille = "weekly_boost_permille"
    }
}