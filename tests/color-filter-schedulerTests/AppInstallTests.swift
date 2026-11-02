import Foundation
import Testing
@testable import color_filter_scheduler

@Suite struct AppInstallTests {
    private func tempHome() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test func onlyApplicationsFoldersAreStable() {
        let home = "/Users/x"
        #expect(AppInstall.isStableInstallPath("/Applications/Night Walker.app", home: home))
        #expect(AppInstall.isStableInstallPath("/Users/x/Applications/Night Walker.app", home: home))
        #expect(!AppInstall.isStableInstallPath("/Volumes/Night Walker/Night Walker.app", home: home))
        #expect(!AppInstall.isStableInstallPath(
            "/private/var/folders/ab/cd/T/AppTranslocation/1234/d/Night Walker.app", home: home))
        #expect(!AppInstall.isStableInstallPath("/Users/x/Downloads/Night Walker.app", home: home))
        #expect(!AppInstall.isStableInstallPath("/Applications/Tools/Night Walker.app", home: home))
        #expect(!AppInstall.isStableInstallPath("/Users/x/Projects/nw/.build/release/color-filter-scheduler", home: home))
    }

    @Test func writesAgentForStableCopyThenIsIdempotent() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let app = "\(home)/Applications/Night Walker.app"
        let exe = "\(app)/Contents/MacOS/color-filter-scheduler"
        #expect(AppInstall.ensureLaunchAgent(bundlePath: app, executable: exe, home: home))
        let url = URL(fileURLWithPath: "\(home)/Library/LaunchAgents/com.flo.color-filter-scheduler.plist")
        #expect(AppInstall.agentExecutable(at: url) == exe)
        #expect(!AppInstall.ensureLaunchAgent(bundlePath: app, executable: exe, home: home))
    }

    @Test func repointsAgentFromOldCopy() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let old = "\(home)/Applications/Color Filter Scheduler.app"
        #expect(AppInstall.ensureLaunchAgent(bundlePath: old, executable: "\(old)/Contents/MacOS/color-filter-scheduler", home: home))
        let new = "/Applications/Night Walker.app"
        let exe = "\(new)/Contents/MacOS/color-filter-scheduler"
        #expect(AppInstall.ensureLaunchAgent(bundlePath: new, executable: exe, home: home))
        let url = URL(fileURLWithPath: "\(home)/Library/LaunchAgents/com.flo.color-filter-scheduler.plist")
        #expect(AppInstall.agentExecutable(at: url) == exe)
    }

    @Test func dmgOrTranslocatedCopyWritesNothing() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let app = "/Volumes/Night Walker/Night Walker.app"
        #expect(!AppInstall.ensureLaunchAgent(bundlePath: app, executable: "\(app)/Contents/MacOS/color-filter-scheduler", home: home))
        #expect(!FileManager.default.fileExists(atPath: "\(home)/Library/LaunchAgents"))
    }

    @Test func dmgCopyNeverQuitsTheInstalledOne() {
        #expect(AppInstall.quitOtherInstances(bundlePath: "/Volumes/Night Walker/Night Walker.app", home: "/Users/x") == 0)
        #expect(AppInstall.quitOtherInstances(bundlePath: "/Users/x/Projects/night-walker/dist/Night Walker.app", home: "/Users/x") == 0)
    }
}
