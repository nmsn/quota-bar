import Foundation
@testable import QuotaBar

final class MockLaunchAtLoginService: LaunchAtLoginServing {
    var isEnabled: Bool = false
    var setEnabledError: Error?
    private(set) var lastSetEnabledValue: Bool?

    func setEnabled(_ enabled: Bool) throws {
        if let setEnabledError { throw setEnabledError }
        lastSetEnabledValue = enabled
        isEnabled = enabled
    }
}
