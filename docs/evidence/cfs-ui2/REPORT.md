# CFS UI polish round (fm/cfs-ui2)

Engine untouched (MediaAccessibility calls, solar math, reconcile timer, config
format) except adding one display-only field: `Settings.locationName`.

## What changed

1. **Darker palette.** New `Palette` in `PanelView.swift`; panel body is now
   near-black `#111214` (`Color(red:0.067,green:0.070,blue:0.078)`), replacing
   the medium grey, to match the "Left" app. Evidence render background updated
   to match.

2. **Run/Pause color coding + contrast.** ON = filled **emerald** block
   (`runOn`) with a subtle emerald border + mint state dot; OFF = faint outlined
   neutral block. The label + icon are **always pure white** (max contrast in
   both states). Emerald is a *cool* hue, orthogonal to the captain's warm/red
   screen tint, so it never blends into the tinted screen the way the old
   orange→pink gradient did. See `panel-on-under-warm-filter.png`: under a
   simulated strong warm/red filter the emerald button still reads as a distinct
   green block with a legible white "Pause" label — no washout.

3. **Header subtitle removed.** The header is just the name "Color Filter"; the
   big Run/Pause button is the sole on/off indicator (no redundant status line).

4. **Location by city name.** Primary input is now a text field ("City — e.g.
   Lisbon") resolved via `CLGeocoder.geocodeAddressString` (CoreLocation, system
   framework, no third-party dep, no location permission, network only at resolve
   time, completion on main queue — UI never blocks). On success it stores + shows
   the coordinates and place name (`Lisbon → 38.71, -9.14`, verified). The precise
   **lat/long fields are retained** as a collapsible "Set lat/long" fine-tune /
   offline override. Failures (no network, unknown city) surface inline in amber
   with no crash.

5. **Popover stay-open.** *Finding:* the popover used `NSPopover` `.transient`,
   which closes on outside click **and whenever the app resigns active**. For an
   `LSUIElement` accessory app (whose active state is fragile), that manifests as
   the panel "closing when the mouse moves away". *Fix:* behavior is now
   `.applicationDefined` (never auto-closes); `AppDelegate` installs a global
   mouse-down monitor (outside click → close) + a local Esc monitor while open,
   and removes them on close. Result: stays open on interaction; dismisses only on
   an explicit outside click or Esc — never on mouse-leave.

## Verification

- `swift build -c release` ✓; `./bundle.sh` produces the signed `.app` ✓.
- Engine live: `--set-enabled 1/0` toggles Color Filters; `--set-intensity`
  drives strength; `--decide --lat 38.7223 --lon -9.1393` computes sunrise/sunset
  and on/off ✓.
- CLGeocoder: `Lisbon → Lisbon, Portugal → 38.7078, -9.1389` ✓.
- Bundled app launched ~4s, created the menu-bar item, no crash, did not flip the
  filter (daytime decision = OFF, live already OFF).
- Screenshots: `panel-front-running.png` (On), `panel-front-paused.png` (Off),
  `panel-settings.png` (Settings), `panel-on-under-warm-filter.png` (washout
  proof), `menubar-icon-light-dark.png`.

## Live state left as found

Before: `enabled=0, SingleColorIntensity=1, type=16`. Restored to exactly that
after testing (intensity had been set to 0.5 during CLI checks). The installed
app's UserDefaults domain (`automationEnabled=1`, Lisbon coords) was not modified.
