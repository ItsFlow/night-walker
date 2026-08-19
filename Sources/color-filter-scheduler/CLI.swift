import Foundation
import AppKit

/// Headless command-line mode used for testing and evidence. It deliberately
/// takes location explicitly on the command line and NEVER reads or writes the
/// app's UserDefaults, so tests can't disturb the user's saved settings.
///
/// Returns an exit code when it handles a command, or nil to fall through to the
/// normal menu-bar GUI.
enum CLI {
    static func run(_ argv: [String]) -> Int32? {
        guard argv.count >= 2 else { return nil }
        let cmd = argv[1]
        guard cmd.hasPrefix("--") else { return nil }
        let opts = parseOptions(Array(argv.dropFirst(2)))

        switch cmd {
        case "--help", "-h":
            printHelp(); return 0
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
            guard let v = opts["value"] ?? opts["_pos0"], let d = Double(v) else {
                errln("--set-intensity needs a 0..1 value"); return 2
            }
            ColorFilters.strength = d
            print(String(format: "strength=%.6f", ColorFilters.strength))
            return 0
        case "--decide", "--reconcile":
            guard let lat = opts["lat"].flatMap(Double.init),
                  let lon = opts["lon"].flatMap(Double.init) else {
                errln("\(cmd) needs --lat <deg> --lon <deg>"); return 2
            }
            let srOff = opts["sr-off"].flatMap(Double.init) ?? 0
            let ssOff = opts["ss-off"].flatMap(Double.init) ?? 0
            let now = Date()
            let d = Scheduler.decide(latitude: lat, longitude: lon,
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
            // Render the redesigned panel to PNGs for evidence. Read-only w.r.t.
            // the live filter (assigns display values in memory only).
            let dir = opts["dir"] ?? opts["_pos0"] ?? "docs/evidence/cfs-ui"
            renderPanel(dir)
            return 0
        case "--selftest":
            // Headless logic test for the popover-dismissal fix. XCTest is not
            // available under CLT-only, so we assert here and return a nonzero
            // exit on failure (usable in CI / a pre-commit gate).
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

    private static func renderPanel(_ dir: String) {
        // ImageRenderer needs an initialized AppKit app on the main thread.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            PanelEvidence.render(to: dir)
        }
    }

    /// Asserts `AppDelegate.clickShouldDismiss` matches the captain's contract:
    /// the panel dismisses ONLY on a genuine outside click, never on an inside
    /// click (any control, on either the short front page or the taller Settings
    /// page) and never on the status item. Returns 0 if all pass, else 1.
    private static func runSelfTest() -> Int32 {
        var passed = 0, failed = 0
        func check(_ name: String, _ cond: Bool) {
            if cond { passed += 1; print("  ok   \(name)") }
            else { failed += 1; print("  FAIL \(name)") }
        }
        // dismiss == true  → the click closes the panel (genuine outside click)
        // dismiss == false → the click is kept (inside the panel / on status item)
        func dismisses(_ p: NSPoint, _ panel: NSRect?, _ status: NSRect?) -> Bool {
            AppDelegate.clickShouldDismiss(at: p, panelFrame: panel, statusItemFrame: status)
        }

        // Realistic frames (screen coords, bottom-left origin). Front page is
        // short; navigating to Settings makes the panel taller (grows downward,
        // top edge fixed just under the menu bar) — both must behave identically.
        let front = NSRect(x: 287, y: 607, width: 314, height: 179)   // observed live size
        let settings = NSRect(x: 287, y: 427, width: 314, height: 359) // taller Settings page
        let statusItem = NSRect(x: 1200, y: 1050, width: 40, height: 24)

        print("selftest: clickShouldDismiss")
        // Inside the FRONT panel — no control click may dismiss it:
        check("front: gear (top-right) kept",     !dismisses(NSPoint(x: front.maxX - 18, y: front.maxY - 16), front, statusItem))
        check("front: Location row kept",         !dismisses(NSPoint(x: front.midX,      y: front.minY + 40), front, statusItem))
        check("front: Run/Pause (center) kept",   !dismisses(NSPoint(x: front.midX,      y: front.midY),      front, statusItem))
        // Inside the taller SETTINGS panel — the reported bug's exact path:
        check("settings: back button kept",       !dismisses(NSPoint(x: settings.minX + 20, y: settings.maxY - 16), settings, statusItem))
        check("settings: Strength/text kept",     !dismisses(NSPoint(x: settings.midX,      y: settings.midY),      settings, statusItem))
        check("settings: lower area (Quit) kept", !dismisses(NSPoint(x: settings.midX,      y: settings.minY + 20), settings, statusItem))
        // The status item is the toggle's job, not the dismiss monitor's:
        check("status item click kept",           !dismisses(NSPoint(x: statusItem.midX, y: statusItem.midY), front, statusItem))
        // Genuine outside clicks DO dismiss:
        check("outside: far top-right dismisses",  dismisses(NSPoint(x: front.maxX + 100, y: front.maxY + 100), front, statusItem))
        check("outside: desktop corner dismisses", dismisses(NSPoint(x: 10, y: 10), front, statusItem))
        check("outside: just past right edge",     dismisses(NSPoint(x: front.maxX + 3, y: front.midY), front, statusItem))
        check("outside: gap below front panel",    dismisses(NSPoint(x: front.midX, y: front.minY - 5), front, statusItem))
        // Defensive: with no panel to protect, a stray event is treated as outside.
        check("defensive: nil frames dismiss",     dismisses(NSPoint(x: 0, y: 0), nil, nil))

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
        menu-bar UI. The following headless commands are for testing/scripting
        and do NOT touch the app's saved settings:

          --get                         print live enabled / type / strength
          --set-enabled 0|1             flip Color Filters master (live)
          --set-intensity 0..1          set Color Filters strength (live)
          --decide  --lat D --lon D [--sr-off M --ss-off M]
                                        print sunrise/sunset + on/off decision (read-only)
          --reconcile --lat D --lon D [--apply]
                                        as --decide; with --apply, set the live state
          --render-panel [dir]          render the UI panels to PNGs (read-only;
                                        default dir: docs/evidence/cfs-ui)
          --selftest                    run headless logic tests (popover dismissal);
                                        exit 0 if all pass (read-only)
          --help                        this help
        """)
    }
}
