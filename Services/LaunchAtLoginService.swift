import Foundation
import ServiceManagement

protocol LaunchAtLoginServing {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginError: Error {
    case registrationFailed(Error)
    case unregistrationFailed(Error)
}

final class LaunchAtLoginService: LaunchAtLoginServing {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                throw LaunchAtLoginError.registrationFailed(error)
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                throw LaunchAtLoginError.unregistrationFailed(error)
            }
        }
    }
}
