# Night Walker

A small macOS menu-bar app that turns Accessibility → Display → **Color Filters**
**ON at sunset** and **OFF at sunrise**. Night Shift for whatever filter you
already picked — grayscale, color tint, color-vision correction, etc.

It flips the master on/off and the strength slider. It never changes the filter
*type*. Choose that once in System Settings.

The name on the panel, in the Finder, and on the disk image is **Night Walker**.
The bundle id `com.flo.color-filter-scheduler` is historical — leftover from
the first working name, kept so existing installs and settings keep working.

## For friends (you have the DMG)

**Needs:** macOS 13 or later, Intel or Apple Silicon. You do **not** need Xcode
or Command Line Tools.

This is not on the App Store and it is not notarized. macOS will warn the first
time because the app is only ad-hoc signed (the free, no-developer-account
signature). That's expected.

1. Open `NightWalker-1.0.0.dmg`.
2. Drag **Night Walker** onto **Applications**.
3. Eject the disk image.
4. In Applications, **right-click Night Walker → Open → Open**. (A regular
   double-click may be blocked by Gatekeeper until you've done this once.)
5. A small icon appears in the menu bar. Click it.
6. Type your city, open the gear, and turn on **Automatic (sunset → sunrise)**.

On first launch, Night Walker registers itself in **System Settings → General →
Login Items** so scheduling resumes after logout or reboot. If macOS marks it as
requiring approval, enable Night Walker there once.

**Run** turns the filter on right now; **Pause** turns it off. With Automatic
on, the solar schedule owns the filter after that — a manual Run/Pause is a
temporary override until the next sunrise/sunset (or the next internal
check, about every five minutes).

To uninstall: quit from the gear menu, disable Night Walker in **System Settings
→ General → Login Items**, then drag Night Walker out of Applications to the
Trash. If you used the builder `install.sh`, run `./uninstall.sh` from a checkout
instead.

## What it looks like

A dark rounded panel from the menu-bar icon, not a stock menu.

- **Front:** name, Run / Pause, a compact city row, a gear.
- **Settings (gear):** strength 0–100% (live), city with optional lat/lon
  fine-tune, Automatic, Quit.

Automation and location are saved in the app's own settings. Strength lives in
macOS Color Filters itself, so it persists even if you quit.

## Honest caveats

- Uses Apple's **private** MediaAccessibility SPI — the same calls System
  Settings uses, so the change hits the live display. A `defaults write` does
  not. Private SPI can break on a macOS update.
- **Not notarized**, not App Store. First launch is right-click → Open.
- Polar day / polar night are handled (all-light / all-dark). No network after
  the one-time city lookup.

## For builders (Command Line Tools)

Needs the macOS Command Line Tools (`swiftc` / `swift`). Full Xcode is not
required. Zero third-party dependencies.

```sh
swift build -c release                 # host-arch binary at .build/release/color-filter-scheduler
./bundle.sh                            # universal (x86_64 + arm64) dist/Night Walker.app, ad-hoc signed
./dmg.sh                               # dist/NightWalker-1.0.0.dmg (calls bundle.sh)
```

Installs to `~/Applications/Night Walker.app` and registers the same
`SMAppService.mainApp` login item used by DMG installs. The bundle id is still
`com.flo.color-filter-scheduler`, so this **refuses** if
`~/Applications/Color Filter Scheduler.app` is present (shared login item and
prefs). Friends should use the DMG, not `install.sh`.

```sh
./install.sh
./uninstall.sh                    # unregister login item, remove app, leave Color Filters OFF
./uninstall.sh --purge-settings   # also delete saved on/off + location
```

Registration and removal use the signed bundled executable. The installer
removes a recognized legacy LaunchAgent during migration; it refuses to remove
an unrelated plist with the same label.

### Headless test CLI

The same binary is a small test CLI. Prefer the **`.build/`** binary, not the
installed `.app` — `--engine-status` / `--engine-reconcile` read this process's
UserDefaults (the bundled app is the captain/friend prefs domain).

```sh
BIN=".build/debug/color-filter-scheduler"
"$BIN" --get                                   # live enabled / type / strength
"$BIN" --decide --lat 48.137 --lon 11.575      # sunrise/sunset + on/off (read-only)
"$BIN" --selftest                              # panel + solar fixtures; exit 0 = pass
tests/run.sh                                   # full local / CI suite
```

`--set-enabled` / `--set-intensity` / `--reconcile --apply` change the live
display (not app settings). Restore Color Filters afterward if you were testing.

### Change the reconcile cadence

Edit `reconcileInterval` in
`Sources/color-filter-scheduler/AppDelegate.swift` (default 300s) and rebuild.

## Requirements

- **Friends:** macOS 13+, Intel or Apple Silicon, the DMG. No CLT.
- **Builders:** macOS 13+ and Command Line Tools.
- Pick a Color Filters *type* once in System Settings → Accessibility →
  Display → Color Filters. This app flips the master and the intensity.
