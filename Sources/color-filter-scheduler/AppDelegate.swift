import AppKit
import SwiftUI

/// Menu-bar-only agent. Owns the NSStatusItem, the reconcile timer, and the
/// custom SwiftUI popover panel (the "Left"-style UI). The scheduling engine
/// (Settings / ReconcileEngine / ColorFilters / Solar) is unchanged; this file
/// is purely the presentation layer plus the timer/wake wiring.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: AppModel!
    private var timer: Timer?
    // Event monitors installed only while the popover is open, so it dismisses
    // on an explicit outside click or Esc — never on mere mouse-leave.
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    // Reconcile cadence. Kept modest so transitions land within a few minutes of
    // the true sunrise/sunset without busy-looping.
    private let reconcileInterval: TimeInterval = 300  // 5 minutes

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        buildStatusItem()
        buildPopover()

        // Reconcile now, on a timer, and on wake from sleep.
        reconcileAndRefresh()
        let t = Timer(timeInterval: reconcileInterval, repeats: true) { [weak self] _ in
            self?.reconcileAndRefresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)

        FileHandle.standardError.write(Data("color-filter-scheduler: menu-bar item created\n".utf8))
    }

    @objc private func didWake(_ note: Notification) {
        reconcileAndRefresh()
    }

    private func reconcileAndRefresh() {
        ReconcileEngine.reconcile()
        model?.refresh()
        updateStatusAppearance()
    }

    // MARK: - Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.image()
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    /// Subtly reflect "filter on" in the menu bar: template images auto-tint, so
    /// we lean on the button's cell state rather than color.
    private func updateStatusAppearance() {
        statusItem?.button?.appearsDisabled = false
    }

    // MARK: - Popover

    private func buildPopover() {
        let pop = NSPopover()
        // `.applicationDefined` (not `.transient`): a transient popover also
        // auto-closes whenever this accessory app *resigns active* — which is
        // exactly what made the panel appear to close "when the mouse moved
        // away", since an LSUIElement's active state is easily lost. We take
        // full control instead: the popover never auto-closes; we dismiss it
        // ourselves only on an explicit outside click or the Esc key (see the
        // monitors in `openPopover`), so it stays open until the user means it.
        pop.behavior = .applicationDefined
        pop.animates = true
        pop.appearance = NSAppearance(named: .darkAqua)   // "Left"-style dark panel
        let root = PanelView(model: model, quit: { NSApp.terminate(nil) })
        pop.contentViewController = NSHostingController(rootView: root)
        popover = pop
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        model.refresh()
        updateStatusAppearance()
        // Activate so the popover's text fields can take keyboard focus.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        // Outside click → dismiss. IMPORTANT: a global monitor is only *supposed*
        // to see events destined for other apps, so the original code closed on
        // any global mouse-down, assuming inside clicks never reach it. That
        // assumption fails for an LSUIElement accessory app: right after the
        // status item shows the popover (and any time the app's active state is
        // lost — which, as the popover behavior note above says, "is easily
        // lost"), the app is not the active app and the popover window is not
        // key, so a click *inside* the popover is delivered as an "other
        // application" event and DID reach this monitor — closing the panel on
        // the very click that opened Settings (the reported bug). Fix: hit-test
        // the click and dismiss only when it lands genuinely outside the panel
        // (and not on the status item, whose own click is the toggle's job).
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
        // Esc → dismiss. Local monitor swallows the key so it doesn't beep.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {   // Esc
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    private func closePopover() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        if popover.isShown { popover.performClose(nil) }
    }

    /// The status-item button's frame in screen coordinates, or nil if unavailable.
    private func statusItemScreenFrame() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Pure, coordinate-space-agnostic dismissal rule (unit-tested via `--selftest`).
    ///
    /// Given a mouse-down `point` and the current on-screen frames of the panel
    /// window and the status-item button (all in the same screen coordinate
    /// space), return `true` only when the click is genuinely OUTSIDE the panel —
    /// i.e. not within the panel window and not on the status item. A click
    /// inside the panel (any control: gear, Location, Run/Pause, Strength, a text
    /// field) must never dismiss it; the status item is excluded because its
    /// click is handled by `togglePopover`.
    static func clickShouldDismiss(at point: NSPoint,
                                   panelFrame: NSRect?,
                                   statusItemFrame: NSRect?) -> Bool {
        if let panelFrame, panelFrame.contains(point) { return false }
        if let statusItemFrame, statusItemFrame.contains(point) { return false }
        return true
    }
}
