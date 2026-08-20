import Foundation
import AppKit
import ColorFilterEngine

/// Headless command-line mode used for testing and evidence.
///
/// Most commands take location on the command line. `--engine-status` and
/// `--engine-reconcile` read the app's saved settings; `--engine-reconcile`,
/// `--set-enabled`, `--set-intensity`, and `--reconcile --apply` can change
/// the live Color Filters master/strength. `--render-panel` is display-only
/// and must not write settings.
///
/// Returns an exit code when it handles a command, or nil to fall through to the
/// normal menu-bar GUI.
enum CLI {
    static func run(_ argv: [String]) -> Int32? {
        guard argv.count >= 2 else { return nil }
        let cmd = argv[1]
        if cmd == "--help" || cmd == "-h" {
            printHelp(); return 0
        }
        guard cmd.hasPrefix("--") else { return nil }
        let opts = parseOptions(Array(argv.dropFirst(2)))

        switch cmd {
        case "--get":
            print("enabled=\(ColorFilters.isEnabled)")
            print("type=\(ColorFilters.filterType)")
            print(String(format: "strength=%.6f", ColorFilters.strength))
            return 0
        case "--set-enabled":
            guard let v = opts["value"] ?? opts["_pos0"], let on = boolArg(v) else {
                errln("--set-enabled needs 0|1"); return 2
            }
            ColorFilters.setEnabled(on)
            print("enabled=\(ColorFilters.isEnabled)")
            return 0
        case "--set-intensity":
            guard let v = opts["value"] ?? opts["_pos0"],
                  let d = FiniteDouble.parse(v), (0...1).contains(d) else {
                errln("--set-intensity needs a 0..1 value"); return 2
            }
            ColorFilters.strength = d
            print(String(format: "strength=%.6f", ColorFilters.strength))
            return 0
        case "--decide", "--reconcile":
            guard let latText = opts["lat"], let lonText = opts["lon"],
                  let coords = Coordinates.parse(latitudeText: latText, longitudeText: lonText) else {
                errln("\(cmd) needs --lat <deg> --lon <deg> (latitude −90…90, longitude −180…180)"); return 2
            }
            guard let srOff = finiteOffset(opts["sr-off"]),
                  let ssOff = finiteOffset(opts["ss-off"]) else {
                errln("\(cmd) --sr-off/--ss-off must be finite numbers of minutes"); return 2
            }
            let now = Date()
            let d = Scheduler.decide(latitude: coords.latitude, longitude: coords.longitude,
                                     sunriseOffsetMinutes: srOff, sunsetOffsetMinutes: ssOff,
                                     now: now)
            print("now: \(fmtDate(now))")
            switch d.sun.kind {
            case .normal:
                print("sunrise: \(fmtDate(d.adjustedSunrise))")
                print("sunset:  \(fmtDate(d.adjustedSunset))")
            case .polarDay: print("sun never sets today (polar day)")
            case .polarNight: print("sun never rises today (polar night)")
            }
            print("decision: \(d.reason) -> want \(d.wantOn ? "ON" : "OFF")")
            if cmd == "--reconcile" && opts["apply"] != nil {
                let before = ColorFilters.isEnabled
                if before != d.wantOn {
                    ColorFilters.setEnabled(d.wantOn)
                    print("applied: \(before ? "ON" : "OFF") -> \(d.wantOn ? "ON" : "OFF") (changed)")
                } else {
                    print("applied: already \(d.wantOn ? "ON" : "OFF") (no change)")
                }
            }
            return 0
        case "--engine-status":
            // Goes through the real Settings/ReconcileEngine path (reads
            // UserDefaults, incl. the -key value argument domain).
            let snap = ReconcileEngine.snapshot()
            print("automationEnabled=\(snap.automationEnabled)")
            print("hasLocation=\(snap.hasLocation)")
            print("currentlyEnabled=\(snap.currentlyEnabled)")
            if let d = snap.decision {
                print("decision=\(d.reason) -> want \(d.wantOn ? "ON" : "OFF")")
            } else {
                print("decision=none (fail-safe: engine will do nothing)")
            }
            return 0
        case "--render-panel":
            // Render the redesigned panel to PNGs. Does not write Settings and
            // does not touch the live filter.
            let dir = opts["dir"] ?? opts["_pos0"] ?? "docs/evidence/cfs-ui"
            do {
                try MainActor.assumeIsolated {
                    try PanelEvidence.render(to: dir)
                }
                return 0
            } catch {
                errln("render-panel failed: \(error.localizedDescription)"); return 1
            }
        case "--selftest":
            // Headless architecture regression for the panel-dismissal fix.
            // XCTest is unavailable under CLT-only, so assert here and return
            // nonzero on failure (usable in CI / a pre-commit gate).
            return runSelfTest()
        case "--engine-reconcile":
            let before = ColorFilters.isEnabled
            let changed = ReconcileEngine.reconcile()
            let after = ColorFilters.isEnabled
            print("engine-reconcile: changed=\(changed) (\(before ? "ON" : "OFF") -> \(after ? "ON" : "OFF"))")
            return 0
        default:
            errln("unknown command: \(cmd)"); printHelp(); return 2
        }
    }

    /// Missing offset → 0 (same as an unset flag). Present but non-finite → nil.
    private static func finiteOffset(_ text: String?) -> Double? {
        guard let text else { return 0 }
        return FiniteDouble.parse(text)
    }

    // Parse `--key value` and bare `--flag` into a dict; bare flags map to "".
    private static func parseOptions(_ args: [String]) -> [String: String] {
        var out: [String: String] = [:]
        var i = 0
        var posIndex = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
                    out[key] = args[i + 1]; i += 2
                } else {
                    out[key] = ""; i += 1
                }
            } else {
                out["_pos\(posIndex)"] = a; posIndex += 1; i += 1
            }
        }
        return out
    }

    /// Guards the key-panel architecture: no popover/global mouse state remains,
    /// and the borderless panel can stay key for both controls and text fields.
    /// Returns 0 if all checks pass, otherwise 1.
    private static func runSelfTest() -> Int32 {
        var passed = 0, failed = 0
        func check(_ name: String, _ cond: Bool) {
            if cond { passed += 1; print("  ok   \(name)") }
            else { failed += 1; print("  FAIL \(name)") }
        }

        // Regression for cfs-ui3: raw global mouse monitoring is not a reliable
        // dismissal boundary for an LSUIElement app. The delegate must own a key
        // panel instead, with no popover/global-click-monitor state left behind.
        let delegateState = Set(Mirror(reflecting: AppDelegate()).children.compactMap(\.label))
        check("presentation uses a key panel with no global mouse monitor",
              delegateState.contains("panel") &&
              !delegateState.contains("popover") &&
              !delegateState.contains("globalClickMonitor"))
        check("panel close path has a resign-key reentrancy guard",
              delegateState.contains("isClosingPanel"))

        _ = NSApplication.shared
        let testPanel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 288, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        check("panel stays key for controls and text until a genuine resign",
              testPanel.canBecomeKey &&
              !testPanel.canBecomeMain &&
              testPanel.isFloatingPanel &&
              !testPanel.becomesKeyOnlyIfNeeded &&
              !testPanel.hidesOnDeactivate)

        print("selftest: \(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }

    private static func boolArg(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "1", "true", "on", "yes": return true
        case "0", "false", "off", "no": return false
        default: return nil
        }
    }

    private static func fmtDate(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        f.timeZone = .current
        return f.string(from: date)
    }

    private static func errln(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    private static func printHelp() {
        print("""
        color-filter-scheduler — menu-bar app. With no arguments it launches the
        menu-bar UI. Headless commands:

          --get                         print live enabled / type / strength
          --set-enabled 0|1             flip Color Filters master (LIVE)
          --set-intensity 0..1          set Color Filters strength (LIVE; finite 0…1)
          --decide  --lat D --lon D [--sr-off M --ss-off M]
                                        print sunrise/sunset + on/off decision (read-only)
          --reconcile --lat D --lon D [--apply]
                                        as --decide; with --apply, set the live state
          --engine-status               read saved settings + live filter; print decision
                                        (does not write settings; does not change the filter)
          --engine-reconcile            apply saved-settings schedule to the live filter
          --render-panel [dir]          render the UI panels to PNGs (does not write
                                        settings or change the live filter;
                                        default dir: docs/evidence/cfs-ui)
          --selftest                    run headless panel-presentation regression;
                                        exit 0 if all pass (read-only)
          --help, -h                    this help

        Invalid coordinates, non-finite offsets, or intensity outside finite 0…1
        exit 2 before any live Color Filters read or write. Negative latitudes
        and longitudes are accepted as values (only --flags start with --).
        """)
    }
}
