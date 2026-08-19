# RCA — panel closes on inside interaction after `b124606`

**Base:** `b124606`

**Environment:** macOS 15.7.7, Swift 6.1.2, Command Line Tools only

**Affected presentation:** `NSPopover(behavior: .applicationDefined)` plus a global
mouse-down monitor and a raw screen-rectangle hit-test.

## Outcome

The popover/global-monitor architecture has been removed. The menu extra now owns a
borderless, nonactivating `StatusPanel` that can become and remain key. It closes only
when that window resigns key status (a real click-away), when Esc is pressed, or when the
status item is explicitly toggled. There is no global mouse monitor and no point/frame
containment decision.

This is intentionally an architectural correction, not another adjustment to the failed
hit-test.

## Reproduction and evidence limit

The captain reproduced the failure on the installed `b124606` build:

1. Open the menu-bar panel.
2. Click Run/Pause or empty panel chrome: the panel closes.
3. Reopen, navigate to Settings, and begin dragging Strength: the panel closes.

This lane cannot replay that physical click under automation. Both
`AXIsProcessTrusted()` and System Events UI scripting returned `false`; synthetic desktop
clicks are dropped before reaching AppKit. Consequently, a real inside-click log of
`NSEvent.mouseLocation` and the popover frame could not be captured. That limitation is
retained here rather than presenting a synthetic coordinate-only test as a reproduction.
The final physical click test remains for firstmate/captain after deployment.

## Trigger, masking condition, visible symptom

| Layer | Proven cause |
|---|---|
| Trigger | The global mouse-down callback evaluates the live inside click as outside and calls `closePopover()`. |
| Masking condition | An `LSUIElement` accessory app and `_NSPopoverWindow` are not reliably active/key immediately after opening, allowing an inside interaction to appear on the global-monitor path. The callback then depends on a lifecycle-sensitive optional `contentViewController.view.window.frame`. |
| Visible symptom | `NSPopover.performClose(nil)` runs and the entire panel disappears before or during the intended control interaction. |

The old `clickShouldDismiss` function is correct only when its point and both rectangles
are current and in the same coordinate space. The installed symptom proves that invariant
does not hold on the failing path: after `b124606`, `performClose` can be reached from the
global callback only when `panelFrame.contains(mouseLocation)` is false or the optional
panel frame is nil. The old self-test explicitly confirmed that a nil frame means
"dismiss" (`defensive: nil frames dismiss`). Thus a stale/nil/mismatched rectangle is the
direct false-dismissal mechanism; the available evidence cannot distinguish which of those
three invalid-frame cases occurred on the captain's physical click.

## Hypotheses and counterfactuals

### H1 — point/window-frame invariant fails: **SUPPORTED (direct trigger)**

- `NSEvent.mouseLocation` was compared with an optional frame reached indirectly through
  the popover content controller.
- The pure function kept an inside point only if that frame existed and contained the
  point; nil was deliberately classified as outside.
- The captain's inside click reached `performClose` after the hit-test fix. By the complete
  close-call graph, the callback therefore saw containment as false.
- The old headless test passed the counterexample `panelFrame=nil → dismiss`, demonstrating
  that a transient missing window reference turns every click, including an inside click,
  into a dismissal.

Disconfirming evidence retained: a previously observed live frame was valid after the
popover settled, and screen-frame math works for representative single- and multi-display
rectangles. The failure is lifecycle-sensitive; this is not evidence that AppKit's settled
screen coordinate systems are universally incompatible.

### H2 — an independent local mouse/resign/SwiftUI path closes it: **RULED OUT**

Repository-wide call tracing at `b124606` found exactly three `closePopover` callers:

1. the status-item toggle;
2. the global mouse-down callback;
3. the local key monitor's Esc branch.

There was no local mouse monitor, `windowDidResignKey`, popover delegate closer, hover
handler, or SwiftUI tap/drag gesture that called close. The prior real-popover
counterfactual also changed front→Settings programmatically with the monitor only logging;
the popover remained shown, ruling out SwiftUI navigation, content resizing, and hosting
controller churn. With the global mouse path disabled, no inside mouse close path remains.

### H3 — `.applicationDefined` plus accessory-app key timing: **SUPPORTED (mask)**

The earlier instrumented real-popover run measured this state immediately after show:

```text
isShown=true appActive=false winIsKey=false winClass=_NSPopoverWindow
activation completed about 48 ms later
```

That proves the assumed "inside events can never reach a global monitor" invariant has a
real timing window in this `LSUIElement` app. It explains why the global callback observes
an inside interaction; H1 explains why the callback then misclassifies it.

## Why the replacement is robust

`StatusPanel` is an `NSPanel` with `.borderless` and `.nonactivatingPanel`, overrides
`canBecomeKey=true`, is floating, does not hide merely because the accessory app deactivates,
and explicitly uses `becomesKeyOnlyIfNeeded=false` because the city/lat/lon fields require
keyboard focus. `makeKeyAndOrderFront` establishes the interaction boundary.

- Run/Pause, the gear, Back, empty chrome, slider drags, switches, and text fields are all
  events inside the same key window. They do not resign it and cannot call the close path.
- Clicking another app or the desktop moves key status away;
  `windowDidResignKey` orders the panel out.
- Esc is the sole local event monitor and closes explicitly.
- No global mouse event, screen point, window number, or rectangle is consulted.
- SwiftUI ideal-size changes resize and re-anchor the same window, so Back/front and
  Settings do not replace the key presentation object.

## Deterministic verification

The regression was observed red before implementation:

```text
FAIL presentation uses a key panel with no global mouse monitor
selftest: 12 passed, 1 failed
```

After replacement, the runtime architecture checks pass:

```text
ok presentation uses a key panel with no global mouse monitor
ok panel close path has a resign-key reentrancy guard
ok panel stays key for controls and text until a genuine resign
selftest: 3 passed, 0 failed
```

`tests/panel-contract.sh` also proves there is no `NSPopover`, global monitor,
`clickShouldDismiss`, or mouse-down close path, and that the key-panel/resign/Esc paths are
present. `tests/ui-contract.sh` guards the seven minimal-copy requirements. AppKit-backed
renders in this directory show the real controls without clipping.

## Manual verification transcript (pending physical input after deployment)

TCC prevents this lane from claiming the final click test. Firstmate/captain should run:

1. Open panel; click empty header/body chrome — **stays open**.
2. Click Run/Pause twice — filter changes live; **panel stays open**.
3. Click gear — Settings appears in the same panel; **stays open**.
4. Drag Strength through several values — effect and percentage change; **stays open for
   the complete drag**.
5. Focus and type into Your location; press Return/Find. Expand Lat/long, type both fields,
   and press Set — fields remain focusable and the panel **stays open**.
6. Toggle Automatic; click Back — front page returns in the same panel.
7. Click the desktop or another app — panel **dismisses**.
8. Reopen and press Esc — panel **dismisses**.

## Engine/state evidence

No engine or persisted-format file changed. Live checks used the real binary and were
restored immediately:

```text
Run/Pause: true -> false -> true
Strength: 0.898860677... -> 0.5 (read back 0.500000) -> restored 1.0
CLGeocoder("Lisbon, Portugal"): resolved 38.7078,-9.1389
Automatic engine: automationEnabled=true, hasLocation=true,
                  after sunset -> want ON, reconcile changed=false
```

Recorded start and final state match exactly:

```text
Color Filters: enabled=true, type=16, strength=1.000000
App config: automationEnabled=1, latitude=38.7223, longitude=-9.1393
```
