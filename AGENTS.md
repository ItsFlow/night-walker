# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

## What this is
**Night Walker**, an `LSUIElement` macOS menu-bar app that turns Accessibility →
Display → Color Filters ON at sunset / OFF at sunrise. Display name is Night
Walker (`CFBundleName` / `CFBundleDisplayName`, `dist/Night Walker.app`); bundle
id `com.flo.color-filter-scheduler` is historical; executable / Swift package
stay `color-filter-scheduler`. CLT-only (no Xcode), zero third-party deps. See
`README.md` and `EVIDENCE.md`.

## UI layer (SwiftUI key panel, "Left" style)
The presentation is a custom near-black, borderless `NSPanel` hosting SwiftUI,
**not** an `NSMenu` or `NSPopover`. Deployment target is **macOS 13**
(Package.swift + bundle.sh
`LSMinimumSystemVersion`) for SwiftUI + `ImageRenderer`. Files:
- `AppModel.swift` — `ObservableObject` bridge; the UI never calls the engine
  directly. Documents the manual-Run/Pause vs. Automatic override rule. Also
  owns city→coords geocoding via `CLGeocoder.geocodeAddressString` (CoreLocation,
  a **system** framework — no third-party dep, no location permission for forward
  geocoding; needs network only at resolve time; completions land on the main
  queue). Resolved place name persists as `Settings.locationName` (display only —
  the engine still runs purely off `latitude`/`longitude`).
- `PanelView.swift` — front page (Run/Pause + Location) and Settings page
  (Strength, **city field** + collapsible lat/lon fine-tune, Automatic, Quit).
  `Palette` holds the near-black + Run/Pause colors. The ON fill is **emerald**
  (a cool hue) not warm orange, so it stays legible while the screen's own
  warm/red Color Filter is applied (a warm fill blends into the tint). Also
  `PanelEvidence` (renders panel PNGs via NSHostingView + `cacheDisplay` —
  `ImageRenderer` stubs AppKit controls).
- Dismissal is a key-window lifecycle, not mouse hit-testing: `StatusPanel`
  stays key for controls and text, `windowDidResignKey` handles a genuine
  click-away, and a local key monitor handles Esc. **Never reintroduce a global
  mouse monitor or raw screen-frame hit-test** for dismissal; both failed for
  inside interactions in this `LSUIElement` app. RCA:
  `docs/evidence/cfs-ui3/RCA.md`. Guarded by `--selftest` and
  `tests/panel-contract.sh`.
- `MenuBarIcon.swift` / `EclipseMark.swift` — programmatic monochrome template
  eclipse (filled disc + two right-side blades). macOS tints the template.
- `tools/make-appicon.swift` — same silhouette for the `.icns`; flares may be
  red on the dock tile. Run by `bundle.sh`. Keep its unit-space numbers in sync
  with `EclipseMark.swift`.
- `--render-panel <dir>` CLI regenerates the AppKit-backed panel screenshots
  (panel architecture: `docs/evidence/cfs-ui3/`; brand glyph: `docs/evidence/nw-brand/`).
Any UI/engine testing MUST restore Color Filters to the pre-test state (see
below); `--render-panel` is read-only w.r.t. the live filter.

## Build / run
- `swift build -c release` → `.build/release/color-filter-scheduler`.
- `./bundle.sh` → assembles + ad-hoc-signs `dist/Night Walker.app`
  (the standard CLT no-Xcode pattern: release build → hand-assembled `.app` →
  `codesign -s -`). `install.sh` installs to `~/Applications` + a launch-at-login
  LaunchAgent (`com.flo.color-filter-scheduler.plist.template`).
- The binary doubles as a headless test CLI (`--get`, `--set-enabled`,
  `--set-intensity`, `--decide/--reconcile --lat --lon [--apply]`,
  `--engine-status`, `--engine-reconcile`, `--selftest` = key-panel architecture
  regression, exit 0 = pass). No args → menu-bar GUI.

## MediaAccessibility SPI (the load-bearing, non-obvious part)
Declared in `Sources/CMediaAccessibility/include/CMediaAccessibility.h`. Private
SPI, linkable under CLT; the framework binary is only in the dyld shared cache
(use `dyld_info -exports` / SDK `.tbd`, not `nm` on the path). Two ABI gotchas
that cost real time — do NOT "simplify" these signatures:
- `MADisplayFilterPrefGetType` takes a **`long category`** arg. A `void` decl
  compiles but silently returns 0 under Swift's calling convention.
- `MADisplayFilterPrefGetSingleColorIntensity` returns **`double`**, not `float`
  (a `float` decl reads garbage ~0).
- Color Filters = **category 1** (`__Color__`); "Color Tint" single-color filter
  = **type 16**. Strength = single-color intensity (0…1).
- Setting via these calls applies **live** (posts the change notification);
  a bare `defaults write` does not.

## Solar math sharp edge
`Solar.swift` `n` (day number) must include the `+ longitude/360` term, or
far-east/-west locations near the UTC day boundary compute the *previous* local
day's sunrise/sunset. Small/European longitudes hide the bug.

## Testing without disturbing the live Mac
This runs on the captain's real Mac. Never leave Color Filters changed: capture
`defaults read com.apple.mediaaccessibility` first and restore exactly. Engine
tests use the `-key value` NSArgumentDomain (not persisted) — note it can't take
**negative** lat/lon (a leading `-` is parsed as a flag); use positive-hemisphere
test locations there.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
