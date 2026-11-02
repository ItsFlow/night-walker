import AppKit
import Foundation

/// What a drag-installed copy (from the DMG) needs that install.sh used to do:
/// launch at login, and no second copy of the same bundle id fighting it.
enum AppInstall {
    static let label = "com.flo.color-filter-scheduler"

    /// Only a copy sitting in an Applications folder registers itself. A copy
    /// running from the DMG, a Gatekeeper translocation path, or a build dir
    /// must not point login launch at a path that will disappear.
    static func isStableInstallPath(_ bundlePath: String, home: String) -> Bool {
        let path = (bundlePath as NSString).standardizingPath
        guard path.hasSuffix(".app") else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "/Applications" || parent == (home as NSString).appendingPathComponent("Applications")
    }

    /// The LaunchAgent plist, same shape as com.flo.color-filter-scheduler.plist.template.
    static func agentPlist(executable: String, logDir: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Background",
            "StandardOutPath": (logDir as NSString).appendingPathComponent("color-filter-scheduler.log"),
            "StandardErrorPath": (logDir as NSString).appendingPathComponent("color-filter-scheduler.err.log"),
        ]
    }

    /// The executable an existing agent plist launches, if it parses.
    static func agentExecutable(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String] else { return nil }
        return args.first
    }

    /// Write (or repoint) the login agent at this copy. Does not bootstrap it:
    /// this copy is already running, and RunAtLoad would start a second one.
    /// Returns true if the file was written.
    @discardableResult
    static func ensureLaunchAgent(bundlePath: String = Bundle.main.bundlePath,
                                  executable: String? = Bundle.main.executablePath,
                                  home: String = NSHomeDirectory()) -> Bool {
        guard let executable, isStableInstallPath(bundlePath, home: home) else { return false }
        let agents = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents")
        let url = agents.appendingPathComponent("\(label).plist")
        if agentExecutable(at: url) == executable { return false }
        let logDir = (home as NSString).appendingPathComponent("Library/Logs")
        do {
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: agentPlist(executable: executable, logDir: logDir),
                format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            FileHandle.standardError.write(Data("color-filter-scheduler: could not write login agent: \(error)\n".utf8))
            return false
        }
    }

    /// Quit any older running copy with our bundle id (for example an older
    /// "Color Filter Scheduler.app"), so two schedulers never fight the filter
    /// and the menu bar shows one eclipse. Only a copy installed in an
    /// Applications folder takes over: opening the app from the DMG or a build
    /// dir must not kill the installed copy. Only copies launched before this
    /// one are quit, so two copies starting together cannot quit each other.
    @discardableResult
    static func quitOtherInstances(bundlePath: String = Bundle.main.bundlePath,
                                   home: String = NSHomeDirectory()) -> Int {
        guard isStableInstallPath(bundlePath, home: home),
              let id = Bundle.main.bundleIdentifier else { return 0 }
        let current = NSRunningApplication.current
        let myLaunch = current.launchDate ?? Date()
        var asked = 0
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: id)
        where app.processIdentifier != current.processIdentifier
            && (app.launchDate ?? .distantPast) <= myLaunch {
            if app.terminate() { asked += 1 }
        }
        return asked
    }
}
