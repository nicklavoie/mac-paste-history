import Foundation
import ServiceManagement

final class LaunchAtLoginManager {
    enum LaunchAtLoginError: LocalizedError {
        case registrationFailed(Error)
        case unregistrationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .registrationFailed(let error):
                return "Could not enable launch at login: \(error.localizedDescription)"
            case .unregistrationFailed(let error):
                return "Could not disable launch at login: \(error.localizedDescription)"
            }
        }
    }

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
