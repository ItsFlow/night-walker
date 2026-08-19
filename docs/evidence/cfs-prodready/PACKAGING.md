# Night Walker packaging

Friend-distributable build: a universal, ad-hoc-signed `.app` inside a
drag-to-Applications DMG. Not notarized, no Developer ID, no App Store.

## What to ship

| Thing | Value |
|---|---|
| Public name | Night Walker |
| App folder | `dist/Night Walker.app` |
| DMG | `dist/NightWalker-1.0.0.dmg` (no spaces) |
| Volume name | Night Walker |
| Executable | `color-filter-scheduler` (unchanged) |
| Bundle id | `com.flo.color-filter-scheduler` (historical) |
| VERSION | `1.0.0` in `bundle.sh` only |

The captain's live app is `~/Applications/Color Filter Scheduler.app`.
`install.sh` now targets `~/Applications/Night Walker.app` so a future
install does not clobber it. Do not run `install.sh` / `uninstall.sh`
from a packaging lane.

## How to build the DMG

From a checkout with Command Line Tools:

```sh
./bundle.sh     # arm64 + x86_64 → lipo → dist/Night Walker.app → ad-hoc sign
./dmg.sh        # calls bundle.sh, then hdiutil UDZO
```

`dmg.sh` stages the `.app` plus a symlink to `/Applications` (standard
drag-install layout) and writes `dist/NightWalker-<version>.dmg`.
VERSION is read from `bundle.sh`. No third-party `create-dmg`.

## lipo expectation

The bundled executable must be a fat Mach-O with both slices:

```
Architectures in the fat file: …/color-filter-scheduler are: x86_64 arm64
```

`bundle.sh` builds `--arch arm64` and `--arch x86_64` separately, then
`lipo -create`. If a slice is missing it errors and dumps `.build/`.

## Gatekeeper

Ad-hoc signed only (`codesign --sign -`). Friends on a fresh Mac:

1. Drag Night Walker → Applications.
2. Right-click the app → Open → Open.
3. A regular double-click is blocked until that one-time exception.

Do not add hardened-runtime entitlements (those need a paid Apple cert).
Do not notarize from this tree.

## Verify (this lane)

Do not open or install the app over the live captain copy. Evidence
captured below after `./bundle.sh`, `./dmg.sh`, and `swift build -c release`.

## Evidence

Host: arm64, Apple Swift 6.1.2, macOS 15. Live captain app
`~/Applications/Color Filter Scheduler.app` was not opened, copied, or
replaced. `install.sh` / `uninstall.sh` were not run.
`~/Applications/Night Walker.app` does not exist.

### `./dmg.sh` (calls `./bundle.sh`)

```
==> Building universal release (arm64 + x86_64)…
Build complete! (58.82s)    # --arch arm64
Build complete! (53.58s)    # --arch x86_64
==> lipo …/.build/arm64-apple-macosx/release/color-filter-scheduler
    + …/.build/x86_64-apple-macosx/release/color-filter-scheduler
Architectures in the fat file: …/dist/Night Walker.app/Contents/MacOS/color-filter-scheduler are: x86_64 arm64
==> Ad-hoc signing
…/dist/Night Walker.app: valid on disk
…/dist/Night Walker.app: satisfies its Designated Requirement
created: …/dist/NightWalker-1.0.0.dmg
-rw-r--r--@ 1 flo  staff   837K  dist/NightWalker-1.0.0.dmg
```

SwiftPM layout on this machine: `.build/arm64-apple-macosx/release/` and
`.build/x86_64-apple-macosx/release/`.

### lipo

```
$ lipo -info "dist/Night Walker.app/Contents/MacOS/color-filter-scheduler"
Architectures in the fat file: dist/Night Walker.app/Contents/MacOS/color-filter-scheduler are: x86_64 arm64
```

### codesign

```
$ codesign --verify --verbose=1 "dist/Night Walker.app"
dist/Night Walker.app: valid on disk
dist/Night Walker.app: satisfies its Designated Requirement

$ codesign -dv --verbose=2 "dist/Night Walker.app"
Executable=…/dist/Night Walker.app/Contents/MacOS/color-filter-scheduler
Identifier=com.flo.color-filter-scheduler
Format=app bundle with Mach-O universal (x86_64 arm64)
CodeDirectory v=20400 size=4439 flags=0x2(adhoc) hashes=132+3 location=embedded
Signature=adhoc
Info.plist entries=11
TeamIdentifier=not set
Sealed Resources version=2 rules=13 files=1
Internal requirements count=0 size=12
```

Info.plist: `CFBundleName` / `CFBundleDisplayName` = Night Walker,
`CFBundleExecutable` = color-filter-scheduler,
`CFBundleIdentifier` = com.flo.color-filter-scheduler,
`LSMinimumSystemVersion` = 13.0, `LSUIElement` = true.

### DMG contents (attach, list, detach — not installed)

Volume name `Night Walker`. Listing of `/Volumes/Night Walker`:

```
lrwxr-xr-x@  Applications -> /Applications
drwxr-xr-x@  Night Walker.app
```

### host-arch `swift build -c release`

```
Build complete! (0.19s)
.build/release/color-filter-scheduler: Mach-O 64-bit executable arm64
Non-fat file: .build/release/color-filter-scheduler is architecture: arm64
```

`--selftest` on the debug binary after the prodready suite: 31 passed,
0 failed (panel architecture + Munich/polar/UTC-day-boundary solar
fixtures + coordinate validation). Panel/UI contracts passed
(including `Text("Night Walker")`).

Re-verified after dropping `--deep` from `codesign`: identifier still
`com.flo.color-filter-scheduler`, `lipo -info` still `x86_64 arm64`,
`codesign --verify` still satisfies the designated requirement.
`dist/NightWalker-1.0.0.dmg` (837K) still present from the earlier
`dmg.sh` run.
