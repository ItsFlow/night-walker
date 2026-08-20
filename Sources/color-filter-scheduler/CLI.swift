import Foundation
import AppKit

/// Headless command-line mode used for testing and evidence.
///
/// `--get` / `--decide` / `--selftest` / `--help` do not read app UserDefaults
/// and do not write Color Filters. `--set-enabled` / `--set-intensity` /
/// `--reconcile --apply` mutate live Color Filters (`com.apple.mediaaccessibility`)
/// but not app settings.
///
/// `--engine-status` / `--engine-reconcile` **do** read `UserDefaults.standard`
/// of *this process*. The bundled app domain is `com.flo.color-filter-scheduler`
/// (captain/friend prefs). Tests must use a `.build/` binary plus `-key value`
/// NSArgumentDomain — never the installed `.app`.
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
        case "--register-login-item":
            return LoginItem.register() ? 0 : 1
        case "--unregister-login-item":
            return LoginItem.unregister() ? 0 : 1
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
            guard let v = opts["value"] ?? opts["_pos0"], let d = Double(v),
                  d.isFinite, d >= 0, d <= 1 else {
                errln("--set-intensity needs a finite 0..1 value"); return 2
            }
            ColorFilters.strength = d
            print(String(format: "strength=%.6f", ColorFilters.strength))
            return 0
        case "--decide", "--reconcile":
            guard let lat = opts["lat"].flatMap(Double.init),
                  let lon = opts["lon"].flatMap(Double.init) else {
                errln("\(cmd) needs --lat <deg> --lon <deg>"); return 2
            }
            guard Scheduler.isValidCoordinate(latitude: lat, longitude: lon) else {
                errln("\(cmd) invalid --lat/--lon (lat in [-90,90], lon in [-180,180], finite)")
                return 2
            }
            let srOff = opts["sr-off"].flatMap(Double.init) ?? 0
            let ssOff = opts["ss-off"].flatMap(Double.init) ?? 0
            guard srOff.isFinite, ssOff.isFinite else {
                errln("\(cmd): --sr-off/--ss-off must be finite"); return 2
            }
            let now: Date
            if let nowStr = opts["now"] {
                guard let parsed = parseISO8601(nowStr) else {
                    errln("\(cmd) invalid --now (expected ISO8601, e.g. 2026-08-18T22:15:00Z)")
                    return 2
                }
                now = parsed
            } else {
                now = Date()
            }
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
            // PNG evidence only. Dir must stay under cwd (no absolute / .. escape).
            // Read-only w.r.t. live Color Filters *and* app UserDefaults.
            let dir = opts["dir"] ?? opts["_pos0"] ?? "docs/evidence/cfs-ui"
            guard let safe = confinedDir(dir) else {
                errln("--render-panel: dir must be cwd or a subdirectory (no absolute / .. escape)")
                return 2
            }
            renderPanel(safe)
            return 0
        case "--selftest":
            // Headless architecture + solar/scheduler regression.
            // XCTest is unavailable under CLT-only, so assert here and return
            // nonzero on failure (usable in CI / a pre-commit gate).
            // Read-only w.r.t. the live Color Filters preference.
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

    /// Resolve `raw` against cwd and require the canonical path stay under cwd.
    /// Symlinks that escape cwd are rejected (`standardizedFileURL` alone
    /// does not resolve them).
    private static func confinedDir(_ raw: String) -> String? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath,
                      isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let url = URL(fileURLWithPath: raw, isDirectory: true, relativeTo: cwd)
            .resolvingSymlinksInPath().standardizedFileURL
        let root = cwd.path
        let path = url.path
        if path == root { return path }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return path
    }

    private static func renderPanel(_ dir: String) {
        // ImageRenderer needs an initialized AppKit app on the main thread.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            PanelEvidence.render(to: dir)
        }
    }

    /// Guards the key-panel architecture plus deterministic solar/scheduler
    /// fixtures. Returns 0 if all checks pass, otherwise 1. Never touches the
    /// live Color Filters preference.
    private static func runSelfTest() -> Int32 {
        var passed = 0, failed = 0
        func check(_ name: String, _ cond: Bool) {
            if cond { passed += 1; print("  ok   \(name)") }
            else { failed += 1; print("  FAIL \(name)") }
        }

        print("selftest: panel architecture")
        check("product name is Night Walker", Product.name == "Night Walker")
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

        print("selftest: solar / scheduler")
        let munichLat = 48.137
        let munichLon = 11.575
        let berlin = TimeZone(identifier: "Europe/Berlin")!

        let munichMidday = utcDate(2026, 8, 18, 12, 0) // 14:00 CEST
        let munichSun = Solar.compute(latitude: munichLat, longitude: munichLon, date: munichMidday)
        check("Munich 2026-08-18 kind is normal", munichSun.kind == .normal)
        check("Munich sunrise exists", munichSun.sunrise != nil)
        check("Munich sunset exists", munichSun.sunset != nil)
        if let sr = munichSun.sunrise, let ss = munichSun.sunset {
            check("Munich CEST sunrise ~06:11 (±3 min)",
                  minutesOff(localHM(sr, berlin), hour: 6, minute: 11) <= 3)
            check("Munich CEST sunset ~20:23 (±3 min)",
                  minutesOff(localHM(ss, berlin), hour: 20, minute: 23) <= 3)
        }

        let munichDay = Scheduler.decide(latitude: munichLat, longitude: munichLon, now: munichMidday)
        check("Munich 12:00 UTC (14:00 CEST) wantOn == false", munichDay.wantOn == false)

        let munichNight = utcDate(2026, 8, 18, 22, 15)
        let munichNightD = Scheduler.decide(latitude: munichLat, longitude: munichLon, now: munichNight)
        check("Munich 22:15 UTC kind is normal", munichNightD.sun.kind == .normal)
        check("Munich 22:15 UTC wantOn == true (dark)", munichNightD.wantOn == true)

        let polarDayNow = utcDate(2026, 6, 21, 12, 0)
        let polarDaySun = Solar.compute(latitude: 80, longitude: 15, date: polarDayNow)
        let polarDayD = Scheduler.decide(latitude: 80, longitude: 15, now: polarDayNow)
        check("80N 21 Jun is polarDay", polarDaySun.kind == .polarDay)
        check("polar day wantOn == false", polarDayD.wantOn == false)

        let polarNightNow = utcDate(2026, 12, 21, 12, 0)
        let polarNightSun = Solar.compute(latitude: 80, longitude: 15, date: polarNightNow)
        let polarNightD = Scheduler.decide(latitude: 80, longitude: 15, now: polarNightNow)
        check("80N 21 Dec is not polarDay", polarNightSun.kind != .polarDay)
        switch polarNightSun.kind {
        case .polarNight:
            check("80N 21 Dec is polarNight", true)
            check("polar night wantOn == true", polarNightD.wantOn == true)
        case .normal:
            let dark: Bool
            if let sr = polarNightD.adjustedSunrise, let ss = polarNightD.adjustedSunset {
                dark = polarNightNow < sr || polarNightNow >= ss
            } else {
                dark = polarNightD.wantOn
            }
            check("80N 21 Dec short-day wantOn matches dark/light", polarNightD.wantOn == dark)
        case .polarDay:
            check("80N 21 Dec must not be polarDay", false)
        }

        let shanghaiNow = utcDate(2026, 8, 18, 0, 30)
        let shanghaiSun = Solar.compute(latitude: 31.23, longitude: 121.47, date: shanghaiNow)
        check("Shanghai 00:30 UTC kind is normal", shanghaiSun.kind == .normal)
        if let sr = shanghaiSun.sunrise, let tz = TimeZone(identifier: "Asia/Shanghai") {
            let day = ymd(sr, tz)
            check("Shanghai sunrise local calendar is 2026-08-18 (not previous UTC day)",
                  day.0 == 2026 && day.1 == 8 && day.2 == 18)
        } else {
            check("Shanghai sunrise exists for day-boundary check", false)
        }

        let farEastLon = 170.0
        let farEastNow = utcDate(2026, 8, 18, 0, 30)
        let farEastSun = Solar.compute(latitude: 0, longitude: farEastLon, date: farEastNow)
        let farEastTz = TimeZone(secondsFromGMT: Int((farEastLon / 15.0 * 3600.0).rounded()))!
        check("170E 00:30 UTC kind is normal", farEastSun.kind == .normal)
        if let sr = farEastSun.sunrise {
            check("170E sunrise local calendar day matches input local day",
                  ymd(sr, farEastTz) == ymd(farEastNow, farEastTz))
        } else {
            check("170E sunrise exists for day-boundary check", false)
        }

        print("selftest: coordinate validation")
        check("reject lat 999", !Scheduler.isValidCoordinate(latitude: 999, longitude: 0))
        check("reject lat 91", !Scheduler.isValidCoordinate(latitude: 91, longitude: 0))
        check("reject lat -91", !Scheduler.isValidCoordinate(latitude: -91, longitude: 0))
        check("reject lon 181", !Scheduler.isValidCoordinate(latitude: 0, longitude: 181))
        check("reject lon -181", !Scheduler.isValidCoordinate(latitude: 0, longitude: -181))
        check("reject NaN lat", !Scheduler.isValidCoordinate(latitude: .nan, longitude: 0))
        check("reject NaN lon", !Scheduler.isValidCoordinate(latitude: 0, longitude: .nan))
        check("reject +inf lat", !Scheduler.isValidCoordinate(latitude: .infinity, longitude: 0))
        check("reject -inf lon", !Scheduler.isValidCoordinate(latitude: 0, longitude: -.infinity))
        check("accept Munich", Scheduler.isValidCoordinate(latitude: munichLat, longitude: munichLon))
        check("accept poles and antimeridian",
              Scheduler.isValidCoordinate(latitude: 90, longitude: 180)
              && Scheduler.isValidCoordinate(latitude: -90, longitude: -180))

        print("selftest: \(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }

    private static func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        return cal.date(from: c)!
    }

    private static func ymd(_ date: Date, _ tz: TimeZone) -> (Int, Int, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func localHM(_ date: Date, _ tz: TimeZone) -> (Int, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    private static func minutesOff(_ hm: (Int, Int), hour: Int, minute: Int) -> Int {
        abs((hm.0 * 60 + hm.1) - (hour * 60 + minute))
    }

    /// Test-only freeze-time parser for `--now`. Internet-date ISO8601.
    private static func parseISO8601(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
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
        color-filter-scheduler — menu-bar app. No args → menu-bar UI.

        Do not read/write app UserDefaults:
          --get / --decide / --selftest / --help
          --set-enabled 0|1             flip Color Filters master (live)
          --set-intensity 0..1          set Color Filters strength (live; finite)
          --reconcile --lat D --lon D [--apply] [--now ISO8601]
                                        as --decide; --apply mutates live Color Filters

        --decide / --reconcile:
          --lat D --lon D [--sr-off M --ss-off M] [--now ISO8601]
          lat in [-90,90], lon in [-180,180], finite; else exit 2.
          --now is test-only (e.g. 2026-08-18T22:15:00Z).

        Read this process's UserDefaults (bundled app = captain/friend prefs):
          --engine-status
          --engine-reconcile            may flip live Color Filters from saved schedule
              Use a .build/ binary plus -key value; never the installed .app.

        Bundled-app lifecycle:
          --register-login-item          register the main app with SMAppService
          --unregister-login-item        remove the SMAppService registration

          --render-panel [dir]          PNGs only; dir must be cwd or a subdirectory
          --help                        this help
        """)
    }
}
