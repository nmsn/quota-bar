import XCTest
@testable import QuotaBar

@MainActor
final class PlatformViewModelTests: XCTestCase {
    func testDefaultActivePlatform() {
        let viewModel = PlatformViewModel()
        XCTAssertTrue(PlatformType.allCases.contains(viewModel.activePlatform))
    }

    func testAllPlatformsReturnsAll() {
        let viewModel = PlatformViewModel()
        XCTAssertEqual(viewModel.allPlatforms.count, PlatformType.allCases.count)
    }

    func testConfiguredPlatformsReturnsArray() {
        let viewModel = PlatformViewModel()
        let platforms = viewModel.allConfiguredPlatforms
        XCTAssertNotNil(platforms)
    }

    func testIsConfiguredReturnsBool() {
        let viewModel = PlatformViewModel()
        for platform in PlatformType.allCases {
            let _ = viewModel.isConfigured(platform)
        }
    }

    func testPlatformDisplayName() {
        let viewModel = PlatformViewModel()
        XCTAssertEqual(viewModel.platformDisplayName(.minimax_cn), "MiniMax")
        XCTAssertEqual(viewModel.platformDisplayName(.deepseek), "DeepSeek")
    }

    func testConfigureAPIKey() {
        let viewModel = PlatformViewModel()
        viewModel.configureAPIKey(for: .deepseek)
        XCTAssertTrue(viewModel.showingConfig)
        XCTAssertEqual(viewModel.configPlatform, .deepseek)
    }

    func testCancelConfig() {
        let viewModel = PlatformViewModel()
        viewModel.configureAPIKey(for: .deepseek)
        viewModel.cancelConfig()
        XCTAssertFalse(viewModel.showingConfig)
        XCTAssertNil(viewModel.configPlatform)
    }

    func testCleanupDoesNotCrash() {
        let viewModel = PlatformViewModel()
        viewModel.startAutoRefresh()
        viewModel.cleanup()
    }

    func testSwitchActivePlatform() {
        let viewModel = PlatformViewModel()
        viewModel.switchActivePlatform(.deepseek)
        XCTAssertEqual(viewModel.activePlatform, .deepseek)
    }
}
