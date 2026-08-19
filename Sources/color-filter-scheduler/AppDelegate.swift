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

        // Outside click (in any other app or the desktop) → dismiss. A global
        // monitor only sees events destined for *other* apps, so clicks inside
        // the popover or on our status item never trigger it.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.closePopover()
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
}
