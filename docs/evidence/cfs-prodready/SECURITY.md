# Night Walker — security audit

Date: 2026-08-19
Scope: adversarial review of this worktree for friend-distribution
readiness. User-facing name **Night Walker**; bundle id remains
`com.flo.color-filter-scheduler`. CLT-only, ad-hoc signed, not notarized,
not App Store. Read-only inspection of Swift sources, SPI header, CLI,
LaunchAgent template, `bundle.sh` / `dmg.sh` / `install.sh` /
`uninstall.sh`, `Package.swift`, `.gitignore`, README.

Constraints honored: do not change SPI signatures, solar math, persisted
keys, or bundle id; no TCC helper; no notarization flow; no running
`install.sh`; no writes to captain `UserDefaults` or live Color Filters
as part of this audit.

**Status (same date, later on `fm/cfs-prodready`):** S1–S8 and S10 are
patched in this branch. Findings below stay as the original audit; the
“Applied on this branch” section at the end records what landed.

## Findings

| id | severity | file | issue | recommended fix (CLT-compatible) |
|---|---|---|---|---|
| S1 | medium | `Sources/color-filter-scheduler/CLI.swift`, `Scheduler.swift` | `--decide` / `--reconcile` accept any `Double` (`nan`, `inf`, `999`). `Double("nan")` succeeds. Solar then produces NaN dates; `now < sr \|\| now >= ss` is both-false, so `wantOn == false`. `--reconcile --apply --lat nan --lon 0` **turns Color Filters OFF** (fail-open). Out-of-range lat/lon still compute a decision and can `--apply`. `--sr-off` / `--ss-off` have the same NaN/Inf hole. Engine path (`Settings.hasValidLocation`) is already fail-closed; CLI is not. | Reject non-finite and out-of-range coords (and non-finite offsets) at the CLI boundary; exit 2. Do not call `Scheduler.decide` / `setEnabled` on garbage. |
| S2 | medium | `Sources/color-filter-scheduler/PanelView.swift` (`PanelEvidence`) | `--render-panel` is **not** settings-read-only. It writes `Settings.shared` lat/lon/`locationName` (UserDefaults) then restores in `defer`. Comments claim isolation from the installed app domain. That is only true for an unpackaged SwiftPM binary. The **bundled** executable (`Night Walker.app`, id `com.flo.color-filter-scheduler`) uses the captain/friend prefs domain. A crash/kill mid-render leaves Lisbon in prefs. README even suggests running the installed binary as `BIN`. | Never assign `Settings.shared` in evidence code. Seed `AppModel` published fields only; fall back `locationDisplay` to `cityText` when Settings has no name. |
| S3 | medium | `Sources/color-filter-scheduler/CLI.swift` | File header and `--help` say the CLI **never** reads/writes app UserDefaults. `--engine-status` / `--engine-reconcile` go through `Settings.shared` / `ReconcileEngine`. On the bundled binary, `--engine-reconcile` applies the **real** saved schedule to the live display. Commands are omitted from `--help` (hidden footgun). Tests that pass `-key value` NSArgumentDomain are safe; running the `.app` binary without those flags is not. | Keep commands for engine tests. Help must say they use **this process’s** defaults domain; instruct tests to use `.build/…`, never the installed `.app`. |
| S4 | medium | `Sources/color-filter-scheduler/ColorFilters.swift`, `CLI.swift` | `--set-intensity` only requires `Double(v) != nil`. `nan` bypasses `min(1, max(0, x))` (both comparisons with NaN are false) and is passed to `MADisplayFilterPrefSetSingleColorIntensity` — live SPI write of NaN. `inf` clamps to 1; `-inf` clamps to 0. | CLI: require `isFinite && 0...1`, else exit 2. Setter: `guard newValue.isFinite else { return }` before clamp. |
| S5 | high | `install.sh`, `uninstall.sh`, LaunchAgent label | `APP_NAME` is now `Night Walker`, so `rm -rf` / `cp -R` no longer smash `~/Applications/Color Filter Scheduler.app`. The LaunchAgent **label** is still `com.flo.color-filter-scheduler` (same as the live captain app). `install.sh` always `launchctl bootout` that label and rewrites `~/Library/LaunchAgents/com.flo.color-filter-scheduler.plist` to point at Night Walker. `uninstall.sh --purge-settings` runs `defaults delete com.flo.color-filter-scheduler` — **captain prefs**, because the bundle id is shared. README’s “will not touch a side-by-side Color Filter Scheduler.app” is true for the `.app` path and **false** for the login item and defaults domain. | Before bootout, require the existing plist’s `ProgramArguments` to contain this script’s `APP_BINARY`. Refuse `--purge-settings` (and refuse install) if `~/Applications/Color Filter Scheduler.app` exists. Verify `CFBundleIdentifier` before `rm -rf`. |
| S6 | low | `install.sh` + `com.flo.color-filter-scheduler.plist.template` | `sed s#__APP_BINARY__#$APP_BINARY#g` interpolates `$HOME` paths raw into XML. `&` / `<` / `>` in a home path break or inject the plist; `#` in the path breaks the sed delimiter. Normal `/Users/name` is safe. | XML-escape (`&` first) and/or write the plist with `PlistBuddy` / a here-doc of escaped values. Keep `ProgramArguments` (spaces in `Night Walker`). |
| S7 | low | `CLI.swift` `--render-panel` | Output dir is unsanitized (`opts["dir"]` / positional / default). `createDirectory(withIntermediateDirectories:)` + `try? png.write` will follow `..` and absolute paths and overwrite `panel-front-running.png` etc. anywhere the user can write. Personal CLI, not a network service. | Standardize the path; refuse unless it is the cwd or a subdirectory of cwd; then create + write. |
| S8 | low | `uninstall.sh` | `rm -rf "$HOME/Applications/Night Walker.app"` with no bundle-id check. A different product named Night Walker would be deleted. After the rename this no longer targets the captain live app (good). Still no check that the binary is ours before `--set-enabled 0`. | `defaults read …/Info.plist CFBundleIdentifier` must equal `com.flo.color-filter-scheduler` before mutate/delete. |
| S9 | info | `bundle.sh` | Ad-hoc `codesign --force --sign - --deep --identifier com.flo.color-filter-scheduler` then `--verify`. Correct for this distribution. `--deep` is redundant (no nested code) and Apple-discouraged for shipping, but not a hole here. Do **not** add `--options runtime` (Hardened Runtime) without Developer ID + notarization. No entitlements plist — keep it that way. DMG (`dmg.sh`) is unsigned; that is expected. | Keep ad-hoc; keep identifier pin; document Gatekeeper. Optional: drop `--deep`. |
| S10 | info | LaunchAgent template | Session type Aqua, `KeepAlive=false`, no `StartInterval`, no MachServices, `ProcessType=Background`. Quit works. Logs under `~/Library/Logs` (user-owned). Missing `AssociatedBundleIdentifiers` only affects how System Settings groups the login item. | Optional: add `AssociatedBundleIdentifiers` = bundle id. |
| S11 | info | logs / PII | GUI writes one stderr line: `color-filter-scheduler: menu-bar item created`. No city, coords, or geocode errors in LaunchAgent logs. Failures stay in the in-memory `geocodeMessage`. CLI `--decide` does not echo lat/lon (caller already passed them). | Do not start logging geocode queries or Settings. |
| S12 | info | network | Only `CLGeocoder.geocodeAddressString` (Apple forward geocode). No `URLSession`, no ATS exception, no location TCC (forward geocode does not need it). Completions on main queue. | Keep; no custom HTTP. |
| S13 | info | SPI | Private MediaAccessibility. Setters apply **live** (post `kMADisplayFilterSettingsChangedNotification`). Signatures in `CMediaAccessibility.h` are **not** accidentally simplified: `GetType(long category)`, intensity getter returns `double`, category `long`, Boolean `unsigned char`. Category 1 / type 16 match evidence. Type is never written. Any local binary that links this SPI can flip Color Filters with no Accessibility TCC prompt — OS design, not an extra hole. | Residual; do not wrap in a helper. Do not “simplify” the header. |
| S14 | info | world-writable / secrets | `mkdir -p` without `chmod 777`; umask-default dirs. `dmg.sh` uses `mktemp -d` + `trap` cleanup. `dist/` gitignored. No tokens, PEM, API keys, or machine-local `/Users/…` in scripts (`$HOME` / `$REPO_DIR`). | No change. |

## What is already good

- Zero third-party dependencies; system frameworks only (AppKit, SwiftUI,
  CoreLocation, MediaAccessibility).
- `ReconcileEngine.reconcile()` no-ops when Automatic is off or
  `hasValidLocation` fails (`isFinite` + lat ∈ [-90,90] + lon ∈ [-180,180]).
- Fresh install defaults Automatic **OFF**, so a first launch does not
  touch the filter until the user opts in.
- `ColorFilters` never sets filter **type** (no SetType SPI declared).
- `--get` / `--decide` (intended) / `--selftest` / `--help` do not write
  Color Filters. `--set-enabled` fail-closes on a non-boolean.
- `AppModel.applyLocation` range-checks lat/lon; NaN comparisons fail
  the range test so NaN is not persisted from the UI.
- LaunchAgent is a per-user Aqua agent, not a daemon; `KeepAlive` false.
- Dismissal uses a local Esc monitor + `windowDidResignKey`, not a
  global mouse tap (no keylogging other apps).
- `dist/` is gitignored. No secrets in tree.
- SPI ABI comments in the header match the empirically pinned calling
  convention. Leave them.
- Friend README already documents unidentified-developer / right-click
  Open. `dmg.sh` is a drag-to-`/Applications` layout (avoids running
  from a translocated DMG as the primary path).
- Uninstall `rm -rf` target is `Night Walker.app`, not the captain’s
  live `Color Filter Scheduler.app`.

## Residual risk (honest)

- **Ad-hoc signature.** Friends see Gatekeeper “unidentified developer”.
  One-time **right-click → Open**. Not Developer ID, not notarized, not
  App Store. A later macOS can tighten this. Unsigned DMG is fine; the
  **app** is what Gatekeeper assesses. After that one-time bypass the
  app runs with full user rights (same as any ad-hoc utility).
- **Private Color Filters SPI.** Undocumented. ABI or category numbers
  can change on a macOS update (the two calling-convention gotchas in
  the header are load-bearing). Setting applies live. There is no TCC
  prompt; that is also how System Settings does it.
- **Shared bundle id** with the captain’s existing
  `Color Filter Scheduler.app`. Two apps, one defaults domain, one
  LaunchAgent label. They must not both be installed as login items.
  Do not change the id (product constraint).
- **Not sandboxed.** Menu-bar agent + LaunchAgent + UserDefaults +
  geocoding. Appropriate for a personal utility; not App Store.
- **`--set-enabled` / `--set-intensity` / `--reconcile --apply`** are
  live mutation tools for tests and recovery. They do not persist *app*
  settings, but they **do** change `com.apple.mediaaccessibility`.
- **No Hardened Runtime / no entitlements.** Correct: HR without a paid
  cert still fails Gatekeeper for downloaded copies and is not worth
  the SPI/TCC risk. Do not invent a permission helper.

## Recommended patches (parent should apply; not applied here)

Priority: S5 (install/uninstall vs live captain), S1+S4 (fail-closed
CLI), S2 (render-panel UserDefaults), S3 (help text), S6–S8 (plist
escape, path confine, bundle-id check).

### 1. CLI: finite coords/offsets, intensity range, path confine, honest help (S1, S3, S4, S7)

```diff
--- a/Sources/color-filter-scheduler/CLI.swift
+++ b/Sources/color-filter-scheduler/CLI.swift
@@ -1,9 +1,12 @@
 /// Headless command-line mode used for testing and evidence. It deliberately
-/// takes location explicitly on the command line and NEVER reads or writes the
-/// app's UserDefaults, so tests can't disturb the user's saved settings.
+/// takes location explicitly on the command line for `--decide`/`--reconcile`.
+/// Those commands do not read app UserDefaults.
+///
+/// `--engine-status` / `--engine-reconcile` **do** read `UserDefaults.standard`
+/// of *this process* (bundled app = `com.flo.color-filter-scheduler`).
+/// Run those only on a `.build/` binary, with `-key value` NSArgumentDomain.
 
         case "--set-intensity":
             guard let v = opts["value"] ?? opts["_pos0"], let d = Double(v) else {
                 errln("--set-intensity needs a 0..1 value"); return 2
             }
+            guard d.isFinite, d >= 0, d <= 1 else {
+                errln("--set-intensity needs a finite 0..1 value"); return 2
+            }
             ColorFilters.strength = d
             print(String(format: "strength=%.6f", ColorFilters.strength))
             return 0
         case "--decide", "--reconcile":
             guard let lat = opts["lat"].flatMap(Double.init),
                   let lon = opts["lon"].flatMap(Double.init) else {
                 errln("\(cmd) needs --lat <deg> --lon <deg>"); return 2
             }
+            guard lat.isFinite, lon.isFinite,
+                  lat >= -90, lat <= 90, lon >= -180, lon <= 180 else {
+                errln("\(cmd): --lat must be finite in [-90,90], --lon finite in [-180,180]"); return 2
+            }
             let srOff = opts["sr-off"].flatMap(Double.init) ?? 0
             let ssOff = opts["ss-off"].flatMap(Double.init) ?? 0
+            guard srOff.isFinite, ssOff.isFinite else {
+                errln("\(cmd): --sr-off/--ss-off must be finite"); return 2
+            }
             let now = Date()
             …
         case "--render-panel":
             let dir = opts["dir"] ?? opts["_pos0"] ?? "docs/evidence/cfs-ui"
-            renderPanel(dir)
+            guard let safe = confinedDir(dir) else {
+                errln("--render-panel: dir must be cwd or a subdirectory (no absolute / .. escape)"); return 2
+            }
+            renderPanel(safe)
             return 0
 
+    /// Resolve `raw` against cwd and require it stay under cwd.
+    private static func confinedDir(_ raw: String) -> String? {
+        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
+        let url = URL(fileURLWithPath: raw, isDirectory: true,
+                      relativeTo: cwd).standardizedFileURL
+        let root = cwd.path
+        let path = url.path
+        if path == root { return path }
+        let prefix = root.hasSuffix("/") ? root : root + "/"
+        guard path.hasPrefix(prefix) else { return nil }
+        return path
+    }
```

Help text (replace the “do NOT touch saved settings” lie):

```
color-filter-scheduler — menu-bar app. No args → menu-bar UI.

Does not read/write app UserDefaults:
  --get / --decide / --selftest / --help
  --set-enabled / --set-intensity / --reconcile --apply
      (these DO mutate live Color Filters / com.apple.mediaaccessibility)

Reads this process's UserDefaults (bundled app = captain/friend prefs):
  --engine-status
  --engine-reconcile     (may flip live Color Filters from saved schedule)
      Use a .build/ binary plus -key value; never the installed .app.

  --render-panel [dir]   PNGs only; dir must be under cwd
```

Defense in depth on the intensity setter:

```diff
--- a/Sources/color-filter-scheduler/ColorFilters.swift
+++ b/Sources/color-filter-scheduler/ColorFilters.swift
     static var strength: Double {
         get { MADisplayFilterPrefGetSingleColorIntensity() }
-        set { MADisplayFilterPrefSetSingleColorIntensity(min(1, max(0, newValue))) }
+        set {
+            guard newValue.isFinite else { return }
+            MADisplayFilterPrefSetSingleColorIntensity(min(1, max(0, newValue)))
+        }
     }
```

### 2. `--render-panel` must not touch UserDefaults (S2)

```diff
--- a/Sources/color-filter-scheduler/PanelView.swift
+++ b/Sources/color-filter-scheduler/PanelView.swift
     static func render(to dir: String) {
         try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
-
-        // Temporarily seed a location in THIS binary's defaults …
-        let savedLat = Settings.shared.latitude, savedLon = Settings.shared.longitude
-        let savedName = Settings.shared.locationName
-        Settings.shared.latitude = 38.72; Settings.shared.longitude = -9.14
-        Settings.shared.locationName = "Lisbon, Portugal"
-        defer {
-            Settings.shared.latitude = savedLat; Settings.shared.longitude = savedLon
-            Settings.shared.locationName = savedName
-        }
-
         let onModel = AppModel()
         …
```

So the front-page screenshot still shows a city without Settings:

```diff
--- a/Sources/color-filter-scheduler/AppModel.swift
+++ b/Sources/color-filter-scheduler/AppModel.swift
     var locationDisplay: String {
         if let name = Settings.shared.locationName, !name.isEmpty { return name }
+        if !cityText.isEmpty { return cityText }
         return locationSummary
     }
```

Live UI unchanged when a resolved `locationName` exists (the usual case).

### 3. LaunchAgent: do not hijack the captain login item (S5, S6, S8)

`install.sh` — XML-escape + refuse to touch a live legacy install:

```diff
--- a/install.sh
+++ b/install.sh
 LABEL="com.flo.color-filter-scheduler"
 APP_NAME="Night Walker"
+LEGACY_APP="$HOME/Applications/Color Filter Scheduler.app"
+
+xml_escape() {
+    # & first so we do not re-escape the inserted entities.
+    local s=$1
+    s=${s//&/&amp;}
+    s=${s//</&lt;}
+    s=${s//>/&gt;}
+    s=${s//\"/&quot;}
+    printf '%s' "$s"
+}
+
+if [[ -d "$LEGACY_APP" ]]; then
+    echo "error: refusing to install: $LEGACY_APP exists." >&2
+    echo "  It shares LaunchAgent label $LABEL and bundle id $LABEL." >&2
+    echo "  Friend path is the DMG; do not run install.sh on the captain Mac." >&2
+    exit 1
+fi

 echo "==> Writing LaunchAgent -> $PLIST"
 mkdir -p "$AGENTS_DIR" "$LOG_DIR"
-sed -e "s#__APP_BINARY__#$APP_BINARY#g" \
-    -e "s#__LOGDIR__#$LOG_DIR#g" \
-    "$REPO_DIR/$LABEL.plist.template" > "$PLIST"
+APP_BINARY_XML="$(xml_escape "$APP_BINARY")"
+LOG_DIR_XML="$(xml_escape "$LOG_DIR")"
+sed -e "s#__APP_BINARY__#$APP_BINARY_XML#g" \
+    -e "s#__LOGDIR__#$LOG_DIR_XML#g" \
+    "$REPO_DIR/$LABEL.plist.template" > "$PLIST"
```

`uninstall.sh`:

```diff
--- a/uninstall.sh
+++ b/uninstall.sh
 LEGACY_APP="$HOME/Applications/Color Filter Scheduler.app"
+
+if [[ -d "$LEGACY_APP" ]]; then
+    echo "error: refusing to uninstall/purge: $LEGACY_APP exists (shared bundle id $LABEL)." >&2
+    exit 1
+fi
+
+if [[ -d "$INSTALLED_APP" ]]; then
+    BID="$(defaults read "$INSTALLED_APP/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
+    if [[ "$BID" != "$LABEL" ]]; then
+        echo "error: $INSTALLED_APP is not $LABEL (id='$BID'); not deleting." >&2
+        exit 1
+    fi
+fi
+
+# Only bootout if the on-disk plist already points at this app binary.
 if [[ -f "$PLIST" ]] && grep -F -q "$APP_BINARY" "$PLIST"; then
     launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
 fi
```

Optional template addition (S10):

```xml
<key>AssociatedBundleIdentifiers</key>
<array>
    <string>com.flo.color-filter-scheduler</string>
</array>
```

### 4. Do not apply (explicit non-fixes)

- Do not change `CMediaAccessibility.h` signatures.
- Do not change solar math or UserDefaults key names.
- Do not add entitlements, Hardened Runtime, sandbox, or a TCC helper.
- Do not notarize or Developer-ID sign.
- Do not rename the bundle id.

## Gatekeeper / friends (residual, not a code bug)

1. Drag **Night Walker** from the DMG onto **Applications** (avoid
   running from the image / App Translocation).
2. **Right-click → Open → Open** once. Double-click stays blocked until
   that exception exists.
3. `spctl --assess` will fail; that is the ad-hoc signature working as
   designed.
4. Replacing the `.app` with a new unsigned/ad-hoc copy can require the
   right-click dance again.
5. After the bypass, the binary can toggle Color Filters with no extra
   prompt. Distribution trust is “you got this DMG from me”.

## Applied on this branch

| id | what landed |
|---|---|
| S1 | CLI rejects non-finite / out-of-range lat/lon and non-finite `--sr-off`/`--ss-off`; `Scheduler.isValidCoordinate` shared with Settings. |
| S2 | `PanelEvidence` no longer writes `Settings.shared`. `locationDisplay` falls back to `cityText`. |
| S3 | CLI header + `--help` distinguish UserDefaults-free commands from `--engine-*`. |
| S4 | `--set-intensity` requires finite 0…1; `ColorFilters.strength` setter ignores NaN. |
| S5 | `install.sh` refuses if `Color Filter Scheduler.app` exists (override: `--replace-login-item`). `uninstall.sh` refuses if that legacy app exists. |
| S6 | `install.sh` copies the template and sets paths with `PlistBuddy` (XML-escaped). |
| S7 | `--render-panel` dir must be cwd or a subdirectory; symlinks that escape cwd are resolved and rejected (Codex P2). |
| S8 | `uninstall.sh` checks `CFBundleIdentifier` before delete; only `bootout`/`rm` plist if it points at Night Walker. |
| S9 | `bundle.sh` ad-hoc `codesign --sign - --identifier …` (no `--deep`, no Hardened Runtime). |
| S10 | LaunchAgent `AssociatedBundleIdentifiers` = bundle id. |

Not applied (intentional): notarization, Hardened Runtime, TCC helper, SPI/solar/key/bundle-id changes.
