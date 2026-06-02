import XCTest
@testable import QuotaBar

final class MiniMaxPlatformTests: XCTestCase {
    var mockNetwork: MockNetworkService!
    var service: MiniMaxPlatformAPIService!

    override func setUp() {
        super.setUp()
        mockNetwork = MockNetworkService()
        service = MiniMaxPlatformAPIService()
    }

    func testFetchUsageSuccess() async throws {
        let json = """
        {
            "model_remains": [
                {
                    "model_name": "general",
                    "current_interval_remaining_percent": 98.0,
                    "current_weekly_remaining_percent": 95.0,
                    "end_time": 1780329600000,
                    "weekly_end_time": 1780848000000
                },
                {
                    "model_name": "video",
                    "current_interval_remaining_percent": 100.0,
                    "current_weekly_remaining_percent": 100.0
                }
            ]
        }
        """
        mockNetwork.mockData = json.data(using: .utf8)
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 200)

        let config = PlatformConfigData(
            platformType: .minimax_cn,
            apiBaseURL: "https://test.com",
            authHeader: "Authorization",
            authPrefix: "Bearer ",
            apiKey: "test-key"
        )

        let result = try await service.fetchUsage(config: config, network: mockNetwork)

        XCTAssertEqual(result.platform, .minimax_cn)
        XCTAssertEqual(result.metrics.count, 2)
        // general 桶: remaining 98% → currentValue=98, totalValue=100
        XCTAssertEqual(result.metrics[0].label, "five_hour")
        XCTAssertEqual(result.metrics[0].currentValue, 98.0)
        XCTAssertEqual(result.metrics[0].totalValue, 100)
        XCTAssertNotNil(result.metrics[0].resetTime)
        // weekly: remaining 95%
        XCTAssertEqual(result.metrics[1].label, "weekly_limit")
        XCTAssertEqual(result.metrics[1].currentValue, 95.0)
        XCTAssertEqual(result.metrics[1].totalValue, 100)
        XCTAssertNotNil(result.metrics[1].resetTime)
    }

    func testFetchUsageNotConfigured() async {
        let config = PlatformConfigData(
            platformType: .minimax_cn,
            apiBaseURL: "https://test.com",
            authHeader: "Authorization",
            authPrefix: "Bearer ",
            apiKey: ""
        )

        do {
            _ = try await service.fetchUsage(config: config, network: mockNetwork)
            XCTFail("Should throw notConfigured")
        } catch {
            XCTAssertEqual(error as? PlatformError, PlatformError.notConfigured(.minimax_cn))
        }
    }

    func testFetchUsageUnauthorized() async {
        mockNetwork.mockData = Data()
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 401)

        let config = PlatformConfigData(
            platformType: .minimax_cn,
            apiBaseURL: "https://test.com",
            authHeader: "Authorization",
            authPrefix: "Bearer ",
            apiKey: "bad-key"
        )

        do {
            _ = try await service.fetchUsage(config: config, network: mockNetwork)
            XCTFail("Should throw unauthorized")
        } catch {
            XCTAssertEqual(error as? PlatformError, PlatformError.unauthorized(.minimax_cn))
        }
    }

    func testFetchUsageNetworkError() async {
        mockNetwork.mockError = URLError(.notConnectedToInternet)

        let config = PlatformConfigData(
            platformType: .minimax_cn,
            apiBaseURL: "https://test.com",
            authHeader: "Authorization",
            authPrefix: "Bearer ",
            apiKey: "test-key"
        )

        do {
            _ = try await service.fetchUsage(config: config, network: mockNetwork)
            XCTFail("Should throw networkError")
        } catch {
            if case .networkError = error as? PlatformError {
                // Expected
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        }
    }

    func testFetchUsageInvalidJSON() async {
        mockNetwork.mockData = "invalid json".data(using: .utf8)
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 200)

        let config = PlatformConfigData(
            platformType: .minimax_cn,
            apiBaseURL: "https://test.com",
            authHeader: "Authorization",
            authPrefix: "Bearer ",
            apiKey: "test-key"
        )

        do {
            _ = try await service.fetchUsage(config: config, network: mockNetwork)
            XCTFail("Should throw decodingError")
        } catch {
            if case .decodingError = error as? PlatformError {
                // Expected
            } else {
                XCTFail("Expected decodingError, got \(error)")
            }
        }
    }

    func testCache() async throws {
        let json = """
        {
            "model_remains": [{
                "model_name": "general",
                "current_interval_remaining_percent": 98.0,
                "current_weekly_remaining_percent": 95.0
            }]
        }
        """
        mockNetwork.mockData = json.data(using: .utf8)
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 200)

        let config = PlatformConfigData(
            platformType: .minimax_cn,
            apiBaseURL: "https://test.com",
            authHeader: "Authorization",
            authPrefix: "Bearer ",
            apiKey: "test-key"
        )

        let result1 = try await service.fetchUsage(config: config, network: mockNetwork)
        let result2 = try await service.fetchUsage(config: config, network: mockNetwork)

        // Second call should use cache (mockNetwork.lastRequest should still be from first call)
        XCTAssertEqual(result1.metrics[0].currentValue, result2.metrics[0].currentValue)
    }

    func testFetchUsageSkipsVideoAndFindsGeneral() async throws {
        // video 排在前面, general 在后面, 仍应正确解析 general
        let json = """
        {
            "model_remains": [
                {
                    "model_name": "video",
                    "current_interval_remaining_percent": 50.0,
                    "current_weekly_remaining_percent": 50.0
                },
                {
                    "model_name": "general",
                    "current_interval_remaining_percent": 80.0,
                    "current_weekly_remaining_percent": 70.0
                }
            ]
        }
        """
        mockNetwork.mockData = json.data(using: .utf8)
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 200)

        let config = PlatformConfigData(
            platformType: .minimax_cn,
            apiBaseURL: "https://test.com",
            authHeader: "Authorization",
            authPrefix: "Bearer ",
            apiKey: "test-key"
        )

        let result = try await service.fetchUsage(config: config, network: mockNetwork)

        // 取的是 general 桶 (80%/70%), 不是 video (50%/50%)
        XCTAssertEqual(result.metrics[0].currentValue, 80.0)
        XCTAssertEqual(result.metrics[1].currentValue, 70.0)
    }

    func testIsHealthyThreshold() async throws {
        // 健康阈值 = 15% 剩余: >= 15% → isHealthy = true, < 15% → isHealthy = false
        let cases: [(remaining: Double, expectedHealthy: Bool)] = [
            (50.0, true),    // 充足
            (15.0, true),    // 临界值
            (14.9, false),   // 临界值下
            (5.0, false),    // 偏低
            (0.0, false)     // 用尽
        ]

        for (index, tc) in cases.enumerated() {
            // service 有 10s 缓存, 每次迭代前清掉, 避免拿到上次的 result
            service.clearCache()

            let json = """
            {
                "model_remains": [{
                    "model_name": "general",
                    "current_interval_remaining_percent": \(tc.remaining),
                    "current_weekly_remaining_percent": 80.0
                }]
            }
            """
            mockNetwork.mockData = json.data(using: .utf8)
            mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 200)

            let config = PlatformConfigData(
                platformType: .minimax_cn,
                apiBaseURL: "https://test.com",
                authHeader: "Authorization",
                authPrefix: "Bearer ",
                apiKey: "test-key"
            )

            let result = try await service.fetchUsage(config: config, network: mockNetwork)
            XCTAssertEqual(
                result.isHealthy, tc.expectedHealthy,
                "case[\(index)] remaining=\(tc.remaining)%, expected isHealthy=\(tc.expectedHealthy)"
            )
        }
    }

    func testFetchUsageMissingGeneralReturnsError() async {
        // 只有 video, 没有 general → 应抛出 invalidResponse
        let json = """
        {
            "model_remains": [{
                "model_name": "video",
                "current_interval_remaining_percent": 100.0,
                "current_weekly_remaining_percent": 100.0
            }]
        }
        """
        mockNetwork.mockData = json.data(using: .utf8)
        mockNetwork.mockResponse = MockNetworkService.makeResponse(url: "https://test.com", statusCode: 200)

        let config = PlatformConfigData(
            platformType: .minimax_cn,
            apiBaseURL: "https://test.com",
            authHeader: "Authorization",
            authPrefix: "Bearer ",
            apiKey: "test-key"
        )

        do {
            _ = try await service.fetchUsage(config: config, network: mockNetwork)
            XCTFail("Should throw invalidResponse")
        } catch {
            XCTAssertEqual(error as? PlatformError, PlatformError.invalidResponse(.minimax_cn))
        }
    }
}
