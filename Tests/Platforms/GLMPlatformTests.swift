import XCTest
@testable import QuotaBar

final class GLMPlatformTests: XCTestCase {
    var mockNetwork: MockNetworkService!
    var service: GLMPlatformAPIService!

    override func setUp() {
        super.setUp()
        mockNetwork = MockNetworkService()
        service = GLMPlatformAPIService()
    }

    private func makeConfig(apiKey: String = "test-key") -> PlatformConfigData {
        PlatformConfigData(
            platformType: .glm_cn,
            apiBaseURL: "https://test.com",
            authHeader: "Authorization",
            authPrefix: "Bearer ",
            apiKey: apiKey
        )
    }

    func testFetchUsageSuccess() async throws {
        // success=true: TOKENS_LIMIT(5h + weekly) + TIME_LIMIT(MCP 月度)
        let json = """
        {
            "code": 200,
            "msg": "success",
            "success": true,
            "data": {
                "limits": [
                    {"type": "TOKENS_LIMIT", "unit": 3, "percentage": 20, "nextResetTime": 1780329600000},
                    {"type": "TOKENS_LIMIT", "unit": 6, "percentage": 10, "nextResetTime": 1780848000000},
                    {"type": "TIME_LIMIT", "usage": 1000, "currentValue": 68, "remaining": 932, "nextResetTime": 1780848000000}
                ],
                "level": "v1"
            }
        }
        """
        mockNetwork.mockData = json.data(using: .utf8)
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 200)

        let result = try await service.fetchUsage(config: makeConfig(), network: mockNetwork)

        XCTAssertEqual(result.platform, .glm_cn)
        XCTAssertEqual(result.metrics.count, 3)
        // TOKENS_LIMIT unit=3 → five_hour, used 20% → remaining 80%
        XCTAssertEqual(result.metrics[0].label, "five_hour")
        XCTAssertEqual(result.metrics[0].currentValue, 80.0)
        XCTAssertEqual(result.metrics[0].totalValue, 100)
        // TOKENS_LIMIT unit=6 → weekly_limit, used 10% → remaining 90%
        XCTAssertEqual(result.metrics[1].label, "weekly_limit")
        XCTAssertEqual(result.metrics[1].currentValue, 90.0)
        // TIME_LIMIT → mcp_monthly, remaining/total 次数
        XCTAssertEqual(result.metrics[2].label, "mcp_monthly")
        XCTAssertEqual(result.metrics[2].currentValue, 932.0)
        XCTAssertEqual(result.metrics[2].totalValue, 1000.0)
    }

    // GLM 业务码错误 (success=false) 必须抛 apiError, 不能静默走空 metrics.
    // 本次修复新增的检查 — 防 key 失效/账户异常时用户看到"无数据"却不知原因.
    func testFetchUsageBusinessError() async {
        let json = #"{"code": 401, "msg": "invalid api key", "success": false, "data": null}"#
        mockNetwork.mockData = json.data(using: .utf8)
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 200)

        do {
            _ = try await service.fetchUsage(config: makeConfig(), network: mockNetwork)
            XCTFail("Should throw apiError when success=false")
        } catch {
            XCTAssertEqual(error as? PlatformError, PlatformError.apiError(.glm_cn, "invalid api key"))
        }
    }

    func testFetchUsageBusinessErrorEmptyMsg() async {
        // success=false 但 msg 空: 应该用兜底文案, 不崩
        let json = #"{"code": 500, "msg": "", "success": false, "data": null}"#
        mockNetwork.mockData = json.data(using: .utf8)
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 200)

        do {
            _ = try await service.fetchUsage(config: makeConfig(), network: mockNetwork)
            XCTFail("Should throw apiError")
        } catch let error as PlatformError {
            XCTAssertEqual(error, PlatformError.apiError(.glm_cn, "GLM request failed"))
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testFetchUsageNotConfigured() async {
        do {
            _ = try await service.fetchUsage(config: makeConfig(apiKey: ""), network: mockNetwork)
            XCTFail("Should throw notConfigured")
        } catch {
            XCTAssertEqual(error as? PlatformError, PlatformError.notConfigured(.glm_cn))
        }
    }

    func testFetchUsageUnauthorized() async {
        mockNetwork.mockData = Data()
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 401)

        do {
            _ = try await service.fetchUsage(config: makeConfig(apiKey: "bad-key"), network: mockNetwork)
            XCTFail("Should throw unauthorized")
        } catch {
            XCTAssertEqual(error as? PlatformError, PlatformError.unauthorized(.glm_cn))
        }
    }
}
