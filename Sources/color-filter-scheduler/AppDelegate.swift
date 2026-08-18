import AppKit

/// Menu-bar-only agent. Owns the NSStatusItem, the reconcile timer, and the
/// three controls (On/Off automation, Strength, Location).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    // Reconcile cadence. Kept modest so transitions land within a few minutes of
    // the true sunrise/sunset without busy-looping.
    private let reconcileInterval: TimeInterval = 300  // 5 minutes

    // Control views we need to refresh when the menu opens.
    private var automationItem: NSMenuItem!
    private var statusLineItem: NSMenuItem!
    private var strengthSlider: NSSlider!
    private var strengthLabel: NSTextField!
    private var latField: NSTextField!
    private var lonField: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()

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
        refreshMenu()
    }

    // MARK: - Status item & menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.righthalf.filled",
                                   accessibilityDescription: "Color Filter Scheduler")
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "Color Filter Scheduler", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        statusLineItem = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)

        menu.addItem(.separator())

        // 1) On/Off — automation master.
        automationItem = NSMenuItem(title: "Automatic (sunset → sunrise)",
                                    action: #selector(toggleAutomation),
                                    keyEquivalent: "")
        automationItem.target = self
        menu.addItem(automationItem)

        menu.addItem(.separator())

        // 2) Strength — real Color Filters intensity.
        let strengthTitle = NSMenuItem(title: "Strength", action: nil, keyEquivalent: "")
        strengthTitle.isEnabled = false
        menu.addItem(strengthTitle)
        menu.addItem(makeStrengthItem())

        menu.addItem(.separator())

        // 3) Location — latitude / longitude.
        let locTitle = NSMenuItem(title: "Location (latitude, longitude)", action: nil, keyEquivalent: "")
        locTitle.isEnabled = false
        menu.addItem(locTitle)
        menu.addItem(makeLocationItem())

        menu.addItem(.separator())

        let reconcileItem = NSMenuItem(title: "Reconcile Now", action: #selector(reconcileNow), keyEquivalent: "r")
        reconcileItem.target = self
        menu.addItem(reconcileItem)

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    private func makeStrengthItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))

        let slider = NSSlider(value: ColorFilters.strength, minValue: 0, maxValue: 1,
                              target: self, action: #selector(strengthChanged(_:)))
        slider.frame = NSRect(x: 16, y: 6, width: 170, height: 20)
        slider.isContinuous = true
        container.addSubview(slider)
        strengthSlider = slider

        let label = NSTextField(labelWithString: "\(Int((ColorFilters.strength * 100).rounded()))%")
        label.frame = NSRect(x: 192, y: 7, width: 44, height: 18)
        label.alignment = .right
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        container.addSubview(label)
        strengthLabel = label

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func makeLocationItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 34))

        let lat = NSTextField(frame: NSRect(x: 16, y: 7, width: 84, height: 22))
        lat.placeholderString = "lat"
        lat.alignment = .center
        if let v = Settings.shared.latitude { lat.stringValue = trimNumber(v) }
        container.addSubview(lat)
        latField = lat

        let lon = NSTextField(frame: NSRect(x: 104, y: 7, width: 84, height: 22))
        lon.placeholderString = "lon"
        lon.alignment = .center
        if let v = Settings.shared.longitude { lon.stringValue = trimNumber(v) }
        container.addSubview(lon)
        lonField = lon

        let apply = NSButton(frame: NSRect(x: 190, y: 5, width: 46, height: 26))
        apply.title = "Set"
        apply.bezelStyle = .rounded
        apply.target = self
        apply.action = #selector(applyLocation)
        container.addSubview(apply)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    // MARK: - Actions

    @objc private func toggleAutomation() {
        Settings.shared.automationEnabled.toggle()
        // Turning ON reconciles immediately; turning OFF leaves the filter as-is.
        reconcileAndRefresh()
    }

    @objc private func strengthChanged(_ sender: NSSlider) {
        ColorFilters.strength = sender.doubleValue
        strengthLabel.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
    }

    @objc private func applyLocation() {
        let lat = Double(latField.stringValue.trimmingCharacters(in: .whitespaces))
        let lon = Double(lonField.stringValue.trimmingCharacters(in: .whitespaces))
        if let lat = lat, lat >= -90, lat <= 90 { Settings.shared.latitude = lat }
        if let lon = lon, lon >= -180, lon <= 180 { Settings.shared.longitude = lon }
        reconcileAndRefresh()
    }

    @objc private func reconcileNow() {
        reconcileAndRefresh()
    }

    // MARK: - Refresh

    private func refreshMenu() {
        guard automationItem != nil else { return }
        let on = Settings.shared.automationEnabled
        automationItem.state = on ? .on : .off

        strengthSlider?.doubleValue = ColorFilters.strength
        strengthLabel?.stringValue = "\(Int((ColorFilters.strength * 100).rounded()))%"

        statusLineItem?.title = statusLine()
    }

    private func statusLine() -> String {
        let snap = ReconcileEngine.snapshot()
        let filter = ColorFilters.isEnabled ? "ON" : "OFF"
        if !snap.automationEnabled {
            return "Filter \(filter) · automation off"
        }
        guard snap.hasLocation, let d = snap.decision else {
            return "Filter \(filter) · set a location"
        }
        switch d.sun.kind {
        case .normal:
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.timeZone = .current
            let sr = d.adjustedSunrise.map { f.string(from: $0) } ?? "—"
            let ss = d.adjustedSunset.map { f.string(from: $0) } ?? "—"
            return "Filter \(filter) · ↑\(sr) ↓\(ss) · want \(d.wantOn ? "ON" : "OFF")"
        case .polarDay:
            return "Filter \(filter) · polar day · want OFF"
        case .polarNight:
            return "Filter \(filter) · polar night · want ON"
        }
    }

    private func trimNumber(_ v: Double) -> String {
        String(format: "%g", v)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }
}
