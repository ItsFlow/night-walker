# color-filter-scheduler

A small, dependency-free macOS **menu-bar app** that automatically turns the
Accessibility → Display → **Color Filters** master toggle **ON at sunset** and
**OFF at sunrise** (Night Shift–style), for a single personal Mac — with a tiny
menu-bar UI to control it.

It flips the master on/off and adjusts the effect **strength**. It never changes
the filter *type* — whatever you chose in System Settings (grayscale, color
tint, protanopia, etc.) is preserved.

- **Menu-bar only.** `LSUIElement` agent: an icon in the menu bar, no Dock icon,
  no main window.
- **Zero third-party dependencies.** Pure Swift + system frameworks (AppKit +
  MediaAccessibility).
- **Builds with `swift build` on Command Line Tools** — no full Xcode, no
  `.xcodeproj`.
- **Self-correcting.** The app reconciles the live state to the solar schedule on
  an internal timer (every ~5 min) and immediately on wake from sleep — robust
  across sleep/wake, reboots, DST, and seasonal drift, with no fixed alarm times.

## The menu-bar UI

A **custom dark rounded key panel** (SwiftUI in a borderless `NSPanel`), not a
stock menu. See `docs/evidence/cfs-ui3/` for current screenshots.

**Front panel** — deliberately tiny:
- **Header** — a day/night glyph, the name, and a bare settings gear.
- **Run / Pause** — the primary control. **Run** turns Color Filters **ON**
  live (the screen visibly changes); **Pause** turns them **OFF** live.
- A compact location row opens the editor.

**Settings** (behind the gear):
- A 0–100% slider for the real macOS Color Filters intensity. Applies live.
- A single city field (Apple geocoding) with collapsible latitude / longitude
  fine-tune fields.
- **Automatic (sunset → sunrise)** — master switch for solar automation.
- **Quit**.

**Manual Run/Pause vs. Automatic.** With Automatic **off** (the default), the
filter follows only the Run/Pause button and the reconcile timer is inert. With
Automatic **on**, the solar scheduler owns the filter (turning it on reconciles
immediately); a manual Run/Pause is then a temporary override until the next
reconcile or sunrise/sunset transition.

Automation on/off and location are saved in the app's own `UserDefaults`.
Strength lives in the OS Color Filters preference itself, so it persists
inherently.

## How it works

- **Toggling + intensity** use Apple's `MediaAccessibility.framework` SPI
  (`MADisplayFilterPrefSetCategoryEnabled` for the master, and
  `MADisplayFilterPrefSetSingleColorIntensity` for strength). This is the same
  mechanism System Settings uses — the calls post the system change notification
  that makes WindowServer apply the change to the live display. (A bare
  `defaults write` does **not** do this.) See [`EVIDENCE.md`](EVIDENCE.md) for how
  the exact symbols were confirmed empirically.
- **Sunrise/sunset** is computed in pure Swift from your latitude/longitude using
  the standard NOAA sunrise equation — no network. Polar day/night are handled
  gracefully (all-light / all-dark).

## Build

```sh
swift build -c release                 # binary at .build/release/color-filter-scheduler
./bundle.sh                            # assemble + ad-hoc sign dist/Color Filter Scheduler.app
```

## Install (to ~/Applications + launch at login)

```sh
./install.sh
```

This builds and bundles the app, installs it to `~/Applications`, writes a
per-user LaunchAgent that launches it at login, and starts it now. Then click the
menu-bar icon; use **Run** to try the filter, and open Settings (the header gear)
to set your location and turn on **Automatic**.

## Test manually (headless commands)

The same binary supports headless commands for testing/scripting. They take the
location explicitly and **do not touch your saved settings**:

```sh
BIN="$HOME/Applications/Color Filter Scheduler.app/Contents/MacOS/color-filter-scheduler"
"$BIN" --get                                   # live enabled / type / strength
"$BIN" --set-enabled 1                          # force Color Filters on
"$BIN" --set-enabled 0                          # force Color Filters off
"$BIN" --set-intensity 0.5                      # set strength to 50% (live)
"$BIN" --decide --lat 48.137 --lon 11.575       # sunrise/sunset + on/off decision (read-only)
"$BIN" --reconcile --lat 48.137 --lon 11.575 --apply   # apply the decision
```

## Change the reconcile cadence

Edit `reconcileInterval` in
`Sources/color-filter-scheduler/AppDelegate.swift` (default 300s) and re-run
`./install.sh`.

## Uninstall

```sh
./uninstall.sh                    # unload agent, remove app, leave Color Filters OFF
./uninstall.sh --purge-settings   # also delete saved on/off + location
```

## Logs

The login-item agent writes to `~/Library/Logs/color-filter-scheduler.log`
(and `.err.log`).

## Requirements

- macOS 13+ with Command Line Tools (`swiftc` / `swift`). Apple Silicon or Intel.
  (The SwiftUI panel UI sets the deployment target to macOS 13.)
- Choose a Color Filters *type* once in System Settings → Accessibility →
  Display → Color Filters. This app flips the master and adjusts intensity; it
  doesn't pick the type.
