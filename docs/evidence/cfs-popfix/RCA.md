# RCA — Settings gear closes the panel instead of navigating

**Branch:** `fm/cfs-popfix`  ·  **Env:** macOS 15.7.7 (Sequoia), Swift 6.1.2, CLT-only
**Symptom (reported):** open the menu-bar panel → click the **Settings gear** → the whole
popover **closes** instead of switching to the in-view Settings page. The Location row
(which also calls `openSettings`) is affected the same way.

## TL;DR

- **Trigger:** the global mouse-down monitor installed while the popover is open
  (`AppDelegate.openPopover`) fires on the **inside** gear click and calls `closePopover()`.
- **Mask:** the app is an `LSUIElement` accessory app. A global monitor is *supposed* to
  see only *other* apps' events, so the old code assumed inside clicks never reach it — but
  right after the status item shows the popover (and any time the accessory app's active
  state is lost, which the code's own comments admit "is easily lost"), the app is **not the
  active app** and the popover window is **not key**, so an inside click is routed as an
  "other-application" event and *does* reach the monitor.
- **Symptom:** `popover.performClose` runs on the very click meant to open Settings.
- **Not the cause:** the content-size change / re-layout on navigation, and NSHostingController
  re-creation / first-responder loss. **Both refuted** by counterfactual (below).
- **Fix:** make the monitor's dismissal a **hit-test** — close only when the click lands
  genuinely *outside* the panel window (and not on the status item). Smallest correct change;
  keeps `behavior = .applicationDefined` (so no app-resign auto-close regression).

## Separating trigger / mask / symptom

| Layer | What it is here |
|---|---|
| **Initiating trigger** | The global click monitor firing on the gear mouse-down and calling `closePopover()`. |
| **Masking condition** | Accessory (`LSUIElement`) app is not active / popover window not key at click time, so an *inside* click is delivered as an "other-app" event that the global monitor observes. |
| **Visible symptom** | `NSPopover.performClose` — the panel disappears. |

## Hypotheses — tested, not assumed

An instrumented harness reproduced the exact production setup (real `NSPopover`,
`behavior = .applicationDefined`, real `PanelView` front/Settings pages, the identical global
monitor matcher) and drove a **real front→Settings page switch programmatically, with NO
click**. Crucially the harness's monitor only *logged*; it never closed the popover. So:

- popover **closes** on the programmatic switch ⇒ resize/navigation path is the trigger (H1/H3);
- popover **stays open** ⇒ resize path is innocent and the real close must come from the *click* (H2).

### H1 — content-size change on navigation (taller Settings page) — **REFUTED**
```
RCA T1-pre-switch  isShown=true  ... appActive=true winIsKey=true
RCA --> switching page front->Settings PROGRAMMATICALLY (no click)
RCA T2-post-switch isShown=true  ... appActive=true winIsKey=true
RCA T3-final       isShown=true  ...
RCA VERDICT resize-path-closes=false monitorFires=0
```
The taller Settings page is real (observed popover window frames: front `314×179`, Settings
grows taller). Yet navigating to it — the exact SwiftUI `withAnimation { page = .settings }`
state change and the resize it triggers — **did not close or re-anchor the popover.** Nothing
in the harness closed it and it stayed shown. **The resize path is not the cause.**

### H3 — NSHostingController re-creation / first-responder loss — **REFUTED**
The page switch is a `switch` inside the *same* `PanelView` body → the same
`NSHostingController`, same root view; no controller is recreated. The harness above exercised
this real path and the popover stayed open (`isShown=true`, `winIsKey=true` throughout). No
dismiss from a hosting/first-responder change.

### H2 — global monitor false-fire on the inside click — **SUPPORTED (the cause)**
The masking condition is demonstrated directly. Immediately after `popover.show` +
`NSApp.activate(ignoringOtherApps:true)` + `makeKey()`:
```
RCA T0-after-show  isShown=true ... appActive=false winIsKey=false winClass=_NSPopoverWindow
RCA ACTIVATION-COMPLETED at ~48ms winIsKey=true      (measured every 25ms)
```
→ There is a real interval after opening where the accessory app is **inactive** and the
popover window is **not key**. In that state an inside click is an "other-application" event
that a global monitor observes.

**Deductive proof of the trigger (closes the loop):**
1. `behavior = .applicationDefined` popovers never auto-close — dismissal is entirely the
   app's responsibility (this is exactly why it was chosen, per the code comments).
2. Therefore the only way the panel closes is `closePopover()`.
3. `closePopover()` is reachable from exactly three sites: `togglePopover` (status-item click),
   the **global click monitor**, and the Esc key monitor.
4. The gear is *inside* the popover → not the status item; it is not Esc; and the
   resize/navigation path is **refuted** above.
5. ∴ the close is the **global click monitor firing on the gear's inside mouse-down**.

The old monitor closed on *any* global mouse-down with **no check that the click was actually
outside the popover** — the fatal flaw. Its "inside clicks never trigger it" claim relies on an
activation invariant that does not hold for an accessory app.

## Disconfirming evidence retained (honest limits)

- **Direct observation of the monitor firing on a real inside click could not be captured**:
  `AXIsProcessTrusted() == false` in this environment, so synthetic `CGEvent` clicks (both
  `.cghidEventTap` and `.cgSessionEventTap`) were **silently dropped** — a contained click at
  the center of our own popover produced `globalFires=0 localFires=0`, i.e. the event never
  entered the NSEvent stream at all. H2 is therefore established by **elimination + the
  demonstrated mask**, not by a captured monitor-fire log. The captain's live click-test is the
  final confirmation (firstmate installs; captain clicks).
- **In the Terminal-launched harness the app activated in ~48 ms**, even when detached from the
  controlling tty. The real menu-bar agent is launched by launchd with no foreground context,
  where Sequoia's tightened `activate(ignoringOtherApps:)` is less likely to succeed — i.e. the
  real app plausibly spends *longer* inactive than the harness, widening the window in which an
  inside click leaks to the monitor. This is consistent with the bug reproducing reliably; it is
  noted as inference, not measured under launchd (installing a login item is out of scope here).

## The fix (smallest correct change)

`AppDelegate.swift` — the global monitor now hit-tests the click instead of closing blindly:

```swift
globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
    matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
    guard let self else { return }
    if AppDelegate.clickShouldDismiss(
        at: NSEvent.mouseLocation,
        panelFrame: self.popover.contentViewController?.view.window?.frame,
        statusItemFrame: self.statusItemScreenFrame()) {
        self.closePopover()
    }
}

// Pure, unit-tested rule: dismiss only when the click is genuinely outside the panel.
static func clickShouldDismiss(at point: NSPoint,
                               panelFrame: NSRect?, statusItemFrame: NSRect?) -> Bool {
    if let panelFrame, panelFrame.contains(point) { return false }       // inside the panel
    if let statusItemFrame, statusItemFrame.contains(point) { return false } // on status item (toggle's job)
    return true                                                          // genuinely outside → dismiss
}
```

Why this is correct for every case:
- **App active** (common): inside clicks are local events the monitor never sees → controls
  work; clicks in other apps reach the monitor, are outside the panel → dismiss. Unchanged, good.
- **App inactive** (the bug): the inside gear click now leaks to the monitor *but* `mouseLocation`
  is inside the panel frame → **kept**. An outside click while inactive is still outside → dismiss.
- **Status item**: excluded so the monitor never races `togglePopover`.
- Keeps `.applicationDefined` → no re-introduction of the app-resign auto-close the design avoided.
- Uses the **live** panel window frame each fire, so the taller Settings page is covered too;
  works across displays (verified with the captain's multi-monitor negative-x frames).

## Counterfactual that proves the fix

Live integration check with the **real** popover + status item on this machine, evaluating the
new rule against **real on-screen frames** (multi-monitor; panel at x≈−9280):
```
VERIFY isShown=true panelFrame=(-9280,159,314,179) statusFrame=(-9280,952.5,26,22)
VERIFY decision gear(inside)=keep  loc(inside)=keep  far(outside)=dismiss(correct)
VERIFY decision statusItem=keep
```
The gear/Location clicks that used to close the panel are now **kept**; a genuine outside click
still **dismisses**. This is the direct counterfactual for H2: with the monitor made
outside-only, the inside gear click no longer dismisses.

## Verification summary

- `--selftest` (headless logic test, CLT-compatible since XCTest is absent): **12/12 pass**,
  covering gear / Location / Run/Pause / Strength / text-field / Back on both the short front
  page and the taller Settings page (all kept), the status item (kept), and four genuinely-outside
  points (dismiss). Debug and release both exit 0.
- `swift build` + `./bundle.sh` → valid ad-hoc-signed `dist/Color Filter Scheduler.app`,
  `LSUIElement=true` preserved.
- Read-only CLI regression (`--get`, `--decide`, `--engine-status`, `--help`) unaffected.
- Raw-binary GUI launch: menu-bar item created, killed <3 s.
- **Engine untouched** (no change to `ColorFilters`/`ReconcileEngine`/`Scheduler`/`Solar`/`Settings`).
- **Captain's Color Filters unchanged** across all runs (before == after every time):
  `__Color__-MADisplayFilterCategoryEnabled=0`, `MADisplayFilterType=16`,
  `MADisplayFilterSingleColorIntensity=1`. firstmate reinstalls after landing.

## What the captain should see after reinstall (final human click-test)

1. Open the panel → click the **gear**: navigates to Settings **in-panel**; panel stays open.
2. Click the **Location** row: same — navigates, stays open.
3. **Back** (chevron) returns to the front page; panel stays open.
4. Click **outside** the panel (any other app / desktop): dismisses. **Esc**: dismisses.
5. Type in the city / lat / lon fields: still typeable. Run/Pause, Strength, Automatic,
   city geocode all still work (engine unchanged).
