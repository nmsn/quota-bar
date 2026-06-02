import XCTest
@testable import QuotaBar

final class PlatformProtocolTests: XCTestCase {
    func testPlatformTypeDisplayNames() {
        XCTAssertEqual(PlatformType.minimax_cn.displayName, "MiniMax (CN)")
        XCTAssertEqual(PlatformType.minimax_en.displayName, "MiniMax (EN)")
        XCTAssertEqual(PlatformType.deepseek.displayName, "DeepSeek")
    }

    func testPlatformTypeAllCases() {
        XCTAssertEqual(PlatformType.allCases.count, 6)
        XCTAssertTrue(PlatformType.allCases.contains(.minimax_cn))
        XCTAssertTrue(PlatformType.allCases.contains(.minimax_en))
        XCTAssertTrue(PlatformType.allCases.contains(.deepseek))
        XCTAssertTrue(PlatformType.allCases.contains(.glm_cn))
        XCTAssertTrue(PlatformType.allCases.contains(.glm_en))
        XCTAssertTrue(PlatformType.allCases.contains(.kimi))
    }

    func testPlatformTypeRawValues() {
        XCTAssertEqual(PlatformType.minimax_cn.rawValue, "minimax_cn")
        XCTAssertEqual(PlatformType.minimax_en.rawValue, "minimax_en")
        XCTAssertEqual(PlatformType.deepseek.rawValue, "deepseek")
    }

    func testPlatformUsageDataEquality() {
        let metric = UsageMetric(label: "Balance", currentValue: 10, totalValue: nil, unit: "USD", resetTime: nil)
        let date = Date()
        let data1 = PlatformUsageData(platform: .deepseek, displayName: "DeepSeek", metrics: [metric], lastUpdated: date, isHealthy: true)
        let data2 = PlatformUsageData(platform: .deepseek, displayName: "DeepSeek", metrics: [metric], lastUpdated: date, isHealthy: true)
        XCTAssertEqual(data1, data2)
    }

    func testUsageMetricEquality() {
        let date = Date()
        let metric1 = UsageMetric(label: "Daily", currentValue: 45, totalValue: 100, unit: "requests", resetTime: date)
        let metric2 = UsageMetric(label: "Daily", currentValue: 45, totalValue: 100, unit: "requests", resetTime: date)
        XCTAssertEqual(metric1, metric2)
    }

    func testUsageMetricWithNilValues() {
        let metric = UsageMetric(label: "Balance", currentValue: 4.5, totalValue: nil, unit: "USD", resetTime: nil)
        XCTAssertNil(metric.totalValue)
        XCTAssertNil(metric.resetTime)
    }

    func testPlatformErrorEquality() {
        XCTAssertEqual(PlatformError.notConfigured(.minimax_cn), PlatformError.notConfigured(.minimax_cn))
        XCTAssertNotEqual(PlatformError.notConfigured(.minimax_cn), PlatformError.notConfigured(.deepseek))
    }
}
