# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

## What this is
An `LSUIElement` macOS menu-bar app that turns Accessibility → Display → Color
Filters ON at sunset / OFF at sunrise, with three controls (On/Off automation,
Strength, Location). CLT-only (no Xcode), zero third-party deps. See `README.md`
and `EVIDENCE.md`.

## Build / run
- `swift build -c release` → `.build/release/color-filter-scheduler`.
- `./bundle.sh` → assembles + ad-hoc-signs `dist/Color Filter Scheduler.app`
  (the standard CLT no-Xcode pattern: release build → hand-assembled `.app` →
  `codesign -s -`). `install.sh` installs to `~/Applications` + a launch-at-login
  LaunchAgent (`com.flo.color-filter-scheduler.plist.template`).
- The binary doubles as a headless test CLI (`--get`, `--set-enabled`,
  `--set-intensity`, `--decide/--reconcile --lat --lon [--apply]`,
  `--engine-status`, `--engine-reconcile`). No args → menu-bar GUI.

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
