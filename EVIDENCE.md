# EVIDENCE — build + live verification

Deliverable: an `LSUIElement` menu-bar app (On/Off automation, Strength, Location)
that reconciles Color Filters to a solar schedule.

Machine: macOS (Darwin 24.6.0), Apple Silicon, **Command Line Tools only** (no
full Xcode). `xcode-select -p` → `/Library/Developer/CommandLineTools`.
Swift 6.1.2. Date of test: 2026-08-18.

All state-changing tests were run against the captain's live Mac and **restored
his original Color Filters state exactly** afterward:

```
ORIGINAL / FINAL (identical):
  MADisplayFilterSingleColorIntensity = 0.9137303829193115
  __Color__-MADisplayFilterCategoryEnabled = 1        # Color Filters = ON
  __Color__-MADisplayFilterType = 16                  # "Color Tint" / single-color
```

## 1. MediaAccessibility SPI — confirmed empirically (not from memory)

Symbols come from the SDK `.tbd` stub + `dyld_info -exports` (the framework
binary lives only in the dyld shared cache). Signatures were then pinned by
runtime probes, which turned up two ABI gotchas worth recording:

| Symbol | Confirmed signature | Note |
|---|---|---|
| `MADisplayFilterPrefCopyCategoriesForCurrentPlatform` | `() -> CFArray` | returns CFNumbers **1…5**; category **1 = Color Filters** (the `__Color__` domain) |
| `MADisplayFilterPrefGetCategoryEnabled` | `(long category) -> Boolean` | Boolean = `unsigned char` |
| `MADisplayFilterPrefSetCategoryEnabled` | `(long category, Boolean)` | posts the live-apply notification |
| `MADisplayFilterPrefGetType` | `(long category) -> long` | **takes the category** — a `void` decl silently reads 0 under Swift's calling convention; `GetType(1)` = 16 |
| `MADisplayFilterPrefGetSingleColorIntensity` | `() -> double` | **returns `double`** — a `float` decl reads garbage (~0) |
| `MADisplayFilterPrefSetSingleColorIntensity` | `(double)` | 0.0…1.0, applies live |

Category 1 = Color Filters was cross-confirmed: it's the only category whose
`GetCategoryEnabled` mirrors `com.apple.mediaaccessibility
"__Color__-MADisplayFilterCategoryEnabled"`.

## 2. The toggle really flips live Color Filters (via the Swift app binary)

```
--set-enabled 0  -> enabled=false | defaults __Color__-…Enabled = 0
--set-enabled 1  -> enabled=true  | defaults __Color__-…Enabled = 1
```

## 3. The Strength slider really changes live intensity (via the Swift app binary)

```
--set-intensity 0.25 -> strength=0.250000 | defaults MADisplayFilterSingleColorIntensity = 0.25
--set-intensity 0.60 -> strength=0.600000 | defaults …SingleColorIntensity = 0.6
--set-intensity 0.9137303829193115 (restore) -> back to original
```

The setter posts `kMADisplayFilterSettingsChangedNotification`, which is what
makes WindowServer apply the change to the display live — the same path System
Settings uses. Genuine live change, not just a `defaults` write.

## 4. `reconcile` maps (location, now) → on/off correctly

Read-only `--decide` at absolute time 2026-08-18 ~22:15 UTC:

| Location | Computed (local) | Decision |
|---|---|---|
| Munich 48.137, 11.575 | ↑06:11 / ↓20:23 CEST, now after sunset | **ON** (dark) ✓ |
| Honolulu 21.3, −157.8 | now between ↑/↓ | **OFF** (light) ✓ |
| Brisbane −27.47, 153.02 | ↑06:15 / ↓17:28 local, now 08:19 | **OFF** (light) ✓ |
| Shanghai 31.23, 121.47 | ↑05:22 / ↓18:34 local, now 06:19 | **OFF** (light) ✓ |
| 80°N, 15°E | sun never sets | **OFF** (polar day) ✓ |
| 80°S, 0° | sun never rises | **ON** (polar night) ✓ |

Munich sunrise/sunset match published values for the date to within ~1 min.
Brisbane/Shanghai (far-east longitudes) validate the day-selection fix in the
solar math: `n` must include the `+ longitude/360` term or those locations
compute the *previous* local day's events.

## 5. Idempotent apply, through the real Swift binary

```
--reconcile daytime --apply : ON -> OFF (changed)
--reconcile daytime --apply : already OFF (no change)   # idempotent
--reconcile night   --apply : OFF -> ON (changed)       # restore
--reconcile night   --apply : already ON (no change)    # idempotent
```

Filter **type (16) and intensity (0.9137) preserved throughout** — only the
master flips; the tool never touches type/intensity.

## 6. The engine does nothing when Off / unconfigured (fail-safe)

Exercised through the real `Settings` + `ReconcileEngine` path (`--engine-*`
commands), driving state via the `-key value` argument domain so **nothing is
persisted to the app's settings domain**:

```
automation OFF, location set   -> engine-reconcile changed=false (ON -> ON)
automation ON,  no location     -> engine-reconcile changed=false (ON -> ON)  (hasLocation=false)
automation ON,  daytime (Shanghai) -> engine-reconcile changed=true  (ON -> OFF)
  run again (same)              -> changed=false (OFF -> OFF)                (idempotent)
```

Before/after each: `defaults read com.flo.color-filter-scheduler` →
"Domain … does not exist" (nothing written; captain's config untouched).

## 7. Build, bundle, and menu-bar app launch

```
swift build -c release  -> Build complete!  (CLT, no Xcode)
./bundle.sh             -> dist/Color Filter Scheduler.app
  Info.plist: OK (plutil -lint); LSUIElement=true; id com.flo.color-filter-scheduler
  codesign:   Signature=adhoc, satisfies its Designated Requirement
```

Menu-bar smoke test (≤5s self-kill, bundled binary):

```
filter BEFORE=1
stderr: "color-filter-scheduler: menu-bar item created"
app stayed running as a persistent agent (killed after 4s)
filter AFTER=1                      # untouched (automation defaults OFF)
app domain after: "does not exist"  # nothing persisted
```

## Not done as part of this task (handled separately, per the brief)

The app / login-item was NOT installed into the live machine, and the captain's
real saved location was never written — all engine tests used the throwaway
argument domain or explicit CLI args. The captain's Color Filters were left
exactly as found (ON, type 16, intensity 0.9137303829193115).
