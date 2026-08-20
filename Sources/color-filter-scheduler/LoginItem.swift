import Foundation
import ServiceManagement

enum LoginItem {
    static func registerIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier == "com.flo.color-filter-scheduler" else { return }

        let service = SMAppService.mainApp
        switch service.status {
        case .notRegistered:
            do {
                try service.register()
            } catch {
                report("could not register launch at login: \(error.localizedDescription)")
            }
        case .requiresApproval:
            report("launch at login requires approval in System Settings > General > Login Items")
        case .enabled:
            break
        case .notFound:
            report("launch-at-login service was not found")
        @unknown default:
            report("launch-at-login service returned an unknown status")
        }
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("color-filter-scheduler: \(message)\n".utf8))
    }
}
