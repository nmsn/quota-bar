import XCTest
@testable import QuotaBar

@MainActor
final class PlatformViewModelTests: XCTestCase {
    func testDefaultActivePlatform() {
        let viewModel = PlatformViewModel()
        XCTAssertTrue(PlatformType.allCases.contains(viewModel.activePlatform))
    }

    func testAllPlatformsReturnsEnabledPlatforms() {
        let viewModel = PlatformViewModel()
        let enabledCount = PlatformType.allCases.filter { $0.isEnabled }.count
        XCTAssertEqual(viewModel.allPlatforms.count, enabledCount)
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
        XCTAssertEqual(viewModel.platformDisplayName(.glm_cn), "GLM")
    }

    func testConfigureAPIKey() {
        let viewModel = PlatformViewModel()
        viewModel.configureAPIKey(for: .glm_cn)
        XCTAssertTrue(viewModel.showingConfig)
        XCTAssertEqual(viewModel.configPlatform, .glm_cn)
    }

    func testCancelConfig() {
        let viewModel = PlatformViewModel()
        viewModel.configureAPIKey(for: .glm_cn)
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
        viewModel.switchActivePlatform(.glm_cn)
        XCTAssertEqual(viewModel.activePlatform, .glm_cn)
    }
}
