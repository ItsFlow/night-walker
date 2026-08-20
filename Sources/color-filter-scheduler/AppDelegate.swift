import AppKit
import SwiftUI

/// A menu-bar panel must be able to become key even though it has no title bar.
/// Keeping it key is the reliable boundary between an inside interaction and a
/// genuine click-away; no global mouse observation or coordinate hit-test is
/// involved.
final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style,
                   backing: backingStoreType, defer: flag)
        configureForStatusItem()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func configureForStatusItem() {
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        isFloatingPanel = true
        // City/lat/lon are editable. Keep the whole panel key, rather than
        // becoming key only when a particular hit view requests it.
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }
}

/// Tracks the ideal SwiftUI size so the borderless panel remains compact when
/// moving between the short front page and the taller Settings page.
final class PanelHostingController<Content: View>: NSHostingController<Content> {
    var preferredSizeDidChange: ((NSSize) -> Void)?

    override var preferredContentSize: NSSize {
        didSet {
            guard preferredContentSize != oldValue else { return }
            preferredSizeDidChange?(preferredContentSize)
        }
    }
}

/// Menu-bar-only agent. Owns the NSStatusItem, the reconcile timer, and the
/// custom SwiftUI key panel (the "Left"-style UI). The scheduling engine
/// (Settings / ReconcileEngine / ColorFilters / Solar) is unchanged; this file
/// is purely the presentation layer plus the timer/wake wiring.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: StatusPanel!
    private var hostingController: PanelHostingController<PanelView>!
    private var model: AppModel!
    private var timer: Timer?
    // Esc is the only event monitor. Outside clicks are represented by the key
    // panel resigning key status; inside clicks never do so.
    private var localKeyMonitor: Any?
    private var isClosingPanel = false

    // Reconcile cadence. Kept modest so transitions land within a few minutes of
    // the true sunrise/sunset without busy-looping.
    private let reconcileInterval: TimeInterval = 300  // 5 minutes

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        buildStatusItem()
        buildPanel()

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
            button.toolTip = "Night Walker"
            button.setAccessibilityTitle("Night Walker")
            button.action = #selector(togglePanel(_:))
            button.target = self
        }
    }

    /// Subtly reflect "filter on" in the menu bar: template images auto-tint, so
    /// we lean on the button's cell state rather than color.
    private func updateStatusAppearance() {
        statusItem?.button?.appearsDisabled = false
    }

    // MARK: - Key panel

    private func buildPanel() {
        let root = PanelView(model: model, quit: { NSApp.terminate(nil) })
        let host = PanelHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]

        let panel = StatusPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 288, height: 1)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.delegate = self
        panel.contentViewController = host
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true

        self.hostingController = host
        self.panel = panel
        host.preferredSizeDidChange = { [weak self] size in
            self?.resizeAndAnchorPanel(to: size)
        }
    }

    @objc private func togglePanel(_ sender: Any?) {
        panel.isVisible ? closePanel() : openPanel()
    }

    private func openPanel() {
        model.refresh()
        updateStatusAppearance()

        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: 288, height: CGFloat.greatestFiniteMagnitude))
        resizeAndAnchorPanel(to: fittingSize)

        installEscapeMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePanel() {
        guard !isClosingPanel else { return }
        isClosingPanel = true
        defer { isClosingPanel = false }
        removeEscapeMonitor()
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func installEscapeMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {   // Esc
                self?.closePanel()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    /// A key panel resigns only when focus genuinely moves elsewhere. Controls,
    /// slider drags, SwiftUI navigation, and text editing all remain in-window
    /// and therefore leave it open.
    func windowDidResignKey(_ notification: Notification) {
        guard !isClosingPanel,
              notification.object as? NSWindow === panel,
              panel.isVisible else { return }
        closePanel()
    }

    private func resizeAndAnchorPanel(to requestedSize: NSSize) {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }

        let width: CGFloat = 288
        let height = ceil(requestedSize.height)
        guard height.isFinite, height > 1 else { return }

        let statusFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: statusFrame.midX - width / 2, y: statusFrame.minY - height,
                      width: width, height: height)
        let gap: CGFloat = 6
        let proposedX = statusFrame.midX - width / 2
        let x = min(max(proposedX, screenFrame.minX), screenFrame.maxX - width)
        let top = min(statusFrame.minY - gap, screenFrame.maxY)
        let y = max(screenFrame.minY, top - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: panel.isVisible)
    }
}
