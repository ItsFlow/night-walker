import Foundation
import Testing
@testable import color_filter_scheduler

@Suite struct PanelEvidenceTests {
    private func liveAppDomain() -> [String: Any]? {
        UserDefaults.standard.persistentDomain(forName: "com.flo.color-filter-scheduler")
    }

    @Test func renderPanelDoesNotWriteSettingsOrLiveAppDomain() throws {
        let beforeLive = liveAppDomain().map { NSDictionary(dictionary: $0) }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfs-panel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let r = try Tool.run(["--render-panel", tmp.path])
        #expect(r.status == 0, "\(r.stderr)\(r.stdout)")

        let afterLive = liveAppDomain().map { NSDictionary(dictionary: $0) }
        #expect(beforeLive == afterLive, "--render-panel must not write the installed app domain")

        let files = [
            "panel-front-running.png",
            "panel-front-paused.png",
            "panel-settings.png",
            "menubar-icon-light-dark.png",
        ]
        for name in files {
            let url = tmp.appendingPathComponent(name)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            #expect(size > 0, "\(name)")
        }
    }

    @Test func renderPanelUnwritableDirectoryExitsNonzero() throws {
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("cfs-not-a-dir-\(UUID().uuidString)")
        try Data("nope".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let r = try Tool.run(["--render-panel", blocker.appendingPathComponent("out").path])
        #expect(r.status != 0)
        #expect(!r.stderr.isEmpty)
    }
}
