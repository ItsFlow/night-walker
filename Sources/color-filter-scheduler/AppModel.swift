import SwiftUI
import Combine

/// UI-facing view model. It is a thin, observable bridge over the (unchanged)
/// engine: `ColorFilters` (live MediaAccessibility state), `Settings` (persisted
/// config) and `ReconcileEngine` (solar scheduler). The UI never talks to the
/// engine directly — it goes through here so state stays in one place.
///
/// Manual Run/Pause vs. Automatic — the one rule to remember:
///  • Automatic OFF (default): the filter follows ONLY the manual Run/Pause
///    button. The reconcile timer is inert (the engine no-ops when automation is
///    off), so nothing ever moves the filter behind the user's back.
///  • Automatic ON: the solar scheduler owns the filter. Turning it on reconciles
///    immediately. A manual Run/Pause while Automatic is on is a *temporary
///    override* — the next reconcile (timer, wake, or the next sunrise/sunset
///    transition) pulls the filter back to what the schedule wants.
final class AppModel: ObservableObject {
    /// Live master state of Color Filters (mirrors `ColorFilters.isEnabled`).
    @Published var filterOn: Bool = ColorFilters.isEnabled
    /// Live effect intensity, 0…1 (mirrors `ColorFilters.strength`).
    @Published var strength: Double = ColorFilters.strength
    /// Persisted master switch for solar automation.
    @Published var automationEnabled: Bool = Settings.shared.automationEnabled
    /// Editable location strings (seed the Settings fields). Empty when unset.
    @Published var latitudeText: String = Settings.shared.latitude.map(AppModel.trim) ?? ""
    @Published var longitudeText: String = Settings.shared.longitude.map(AppModel.trim) ?? ""
    /// One-line human status shown under the app name.
    @Published var statusText: String = ""

    init() {
        refresh()
    }

    // MARK: - Front panel actions

    /// Run = turn the filter ON right now, live, so the screen visibly changes.
    func run() {
        ColorFilters.setEnabled(true)
        refresh()
    }

    /// Pause = turn the filter OFF right now, live.
    func pause() {
        ColorFilters.setEnabled(false)
        refresh()
    }

    func toggleRun() {
        filterOn ? pause() : run()
    }

    // MARK: - Settings actions

    func setStrength(_ value: Double) {
        ColorFilters.strength = value
        strength = ColorFilters.strength
    }

    /// Turn solar automation on/off. Turning it on hands control to the
    /// scheduler and reconciles immediately so the filter snaps to the schedule.
    func setAutomation(_ on: Bool) {
        Settings.shared.automationEnabled = on
        automationEnabled = on
        ReconcileEngine.reconcile()
        refresh()
    }

    /// Commit the lat/lon text fields to persisted settings (validated), then
    /// reconcile so a schedule change takes effect at once.
    func applyLocation() {
        if let lat = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
           lat >= -90, lat <= 90 {
            Settings.shared.latitude = lat
        }
        if let lon = Double(longitudeText.trimmingCharacters(in: .whitespaces)),
           lon >= -180, lon <= 180 {
            Settings.shared.longitude = lon
        }
        ReconcileEngine.reconcile()
        refresh()
    }

    var hasLocation: Bool { Settings.shared.hasValidLocation }

    /// Short "37.77, -122.42" style summary, or a prompt when unset.
    var locationSummary: String {
        guard let lat = Settings.shared.latitude, let lon = Settings.shared.longitude,
              Settings.shared.hasValidLocation else {
            return "Not set"
        }
        return "\(Self.trim(lat)), \(Self.trim(lon))"
    }

    // MARK: - Refresh (pull live engine state into the published properties)

    func refresh() {
        filterOn = ColorFilters.isEnabled
        strength = ColorFilters.strength
        automationEnabled = Settings.shared.automationEnabled
        statusText = Self.makeStatus()
    }

    private static func makeStatus() -> String {
        let on = ColorFilters.isEnabled ? "On" : "Off"
        return Settings.shared.automationEnabled ? "\(on) · auto" : on
    }

    static func trim(_ v: Double) -> String { String(format: "%g", v) }
}
