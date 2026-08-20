# Night Walker

Color Filters on at sunset, off at sunrise. A tiny macOS menu-bar app.

Click the eclipse: Run or Pause, name a city, flip Automatic. It leaves
whatever filter type you picked in System Settings → Accessibility → Display
→ Color Filters alone — only the master switch and the strength move. It
reconciles on a timer (~5 min) and when the Mac wakes, so sleep, DST, and the
seasons don't leave the filter stuck. The timer polls; it does not schedule an
extra exact sunrise/sunset alarm.

The bundle id `com.flo.color-filter-scheduler` is historical.

## Build

```sh
swift build -c release                 # binary at .build/release/color-filter-scheduler
./bundle.sh                            # assemble + ad-hoc sign dist/Night Walker.app
```

## Install (to ~/Applications + launch at login)

```sh
./install.sh
```

This builds and bundles the app, installs it to `~/Applications/Night Walker.app`,
writes a per-user LaunchAgent that launches it at login, and starts it now. Click
the menu-bar eclipse; use **Run** to try the filter, then open Settings (the
header gear) to set your city and turn on **Automatic**.

## Test manually (headless commands)

The same binary supports headless commands for testing/scripting. `--decide`
takes the location on the command line and does not read saved settings.
`--engine-status` / `--engine-reconcile` *do* read saved settings; enabled,
intensity, and `--reconcile --apply` / `--engine-reconcile` change the live
filter. Invalid coordinates, non-finite offsets, or intensity outside finite
`0…1` exit 2 before any live read or write.

```sh
BIN="$HOME/Applications/Night Walker.app/Contents/MacOS/color-filter-scheduler"
"$BIN" --get                                   # live enabled / type / strength
"$BIN" --set-enabled 1                          # force Color Filters on
"$BIN" --set-enabled 0                          # force Color Filters off
"$BIN" --set-intensity 0.5                      # set strength to 50% (live)
"$BIN" --decide --lat 48.137 --lon 11.575       # sunrise/sunset + on/off decision (read-only)
"$BIN" --reconcile --lat 48.137 --lon 11.575 --apply   # apply the decision
"$BIN" --engine-status                          # saved settings + live decision
"$BIN" -h                                       # help
```

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
- Choose a Color Filters *type* once in System Settings → Accessibility →
  Display → Color Filters. This app flips the master and adjusts intensity; it
  doesn't pick the type.
