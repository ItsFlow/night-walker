import Foundation
import ServiceManagement

enum LoginItem {
    static func registerIfNeeded() {
        guard isBundledApp else { return }
        _ = register()
    }

    static func register() -> Bool {
        guard isBundledApp else {
            report("login-item commands require the bundled app")
            return false
        }

        let service = SMAppService.mainApp
        switch service.status {
        case .notRegistered:
            do {
                try service.register()
                report("launch at login registered")
                return true
            } catch {
                report("could not register launch at login: \(error.localizedDescription)")
                return false
            }
        case .requiresApproval:
            report("launch at login requires approval in System Settings > General > Login Items")
            return true
        case .enabled:
            return true
        case .notFound:
            report("launch-at-login service was not found")
            return false
        @unknown default:
            report("launch-at-login service returned an unknown status")
            return false
        }
    }

    static func unregister() -> Bool {
        guard isBundledApp else {
            report("login-item commands require the bundled app")
            return false
        }

        let service = SMAppService.mainApp
        switch service.status {
        case .enabled, .requiresApproval:
            do {
                try service.unregister()
                report("launch at login unregistered")
                return true
            } catch {
                report("could not unregister launch at login: \(error.localizedDescription)")
                return false
            }
        case .notRegistered, .notFound:
            return true
        @unknown default:
            report("launch-at-login service returned an unknown status")
            return false
        }
    }

    private static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.bundleIdentifier == "com.flo.color-filter-scheduler"
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("color-filter-scheduler: \(message)\n".utf8))
    }
}
