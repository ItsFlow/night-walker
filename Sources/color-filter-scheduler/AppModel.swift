import SwiftUI
import Combine
import CoreLocation

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
    /// Editable location strings (seed the Settings fine-tune fields). Empty when unset.
    @Published var latitudeText: String = Settings.shared.latitude.map(AppModel.trim) ?? ""
    @Published var longitudeText: String = Settings.shared.longitude.map(AppModel.trim) ?? ""
    /// The city-name text the user types to geocode (primary location input).
    @Published var cityText: String = Settings.shared.locationName ?? ""
    /// Inline feedback for the city geocode (resolved place, or an error).
    @Published var geocodeMessage: String = ""
    /// Whether the last geocode outcome was a success (drives message color).
    @Published var lastGeocodeOK: Bool = true
    /// True while a geocode request is in flight, so the UI can show progress.
    @Published var isGeocoding: Bool = false
    /// One-line human status (kept for scripting/evidence; no longer shown in UI).
    @Published var statusText: String = ""

    /// Forward-geocoder for the city → coordinates lookup. CLGeocoder's forward
    /// geocoding needs no location permission (it's an address lookup), only
    /// network at resolve time; completions arrive on the main queue.
    private let geocoder = CLGeocoder()

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

    /// Resolve the typed city name to coordinates via CoreLocation (Apple's
    /// built-in geocoder — a system framework, no third-party dependency). On
    /// success it stores the coordinates + place name, mirrors them into the
    /// fine-tune fields, and reconciles. Failures surface inline; the UI thread
    /// is never blocked (the request is async, completion on the main queue).
    func resolveCity() {
        let query = cityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            lastGeocodeOK = false
            geocodeMessage = "Type a city name, e.g. Lisbon."
            return
        }
        isGeocoding = true
        lastGeocodeOK = true
        geocodeMessage = "Resolving…"
        geocoder.cancelGeocode()
        geocoder.geocodeAddressString(query) { [weak self] placemarks, error in
            guard let self = self else { return }
            self.isGeocoding = false
            if let error = error {
                let msg = Self.friendlyGeocodeError(error)
                if msg.isEmpty { return }   // canceled by a newer request; keep prior state
                self.lastGeocodeOK = false
                self.geocodeMessage = msg
                return
            }
            guard let placemark = placemarks?.first, let loc = placemark.location else {
                self.lastGeocodeOK = false
                self.geocodeMessage = "Couldn’t find “\(query)”. Check the spelling or set lat/long below."
                return
            }
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            let name = Self.placeName(placemark, fallback: query)
            Settings.shared.latitude = lat
            Settings.shared.longitude = lon
            Settings.shared.locationName = name
            self.latitudeText = Self.trim(lat)
            self.longitudeText = Self.trim(lon)
            self.cityText = name
            self.lastGeocodeOK = true
            self.geocodeMessage = "\(name) · \(Self.trim(lat)), \(Self.trim(lon))"
            ReconcileEngine.reconcile()
            self.refresh()
        }
    }

    /// Map a CLGeocoder error to a short, human message (no network, not found…).
    private static func friendlyGeocodeError(_ error: Error) -> String {
        if let clError = error as? CLError {
            switch clError.code {
            case .network:
                return "No network. Connect and retry, or set lat/long below."
            case .geocodeFoundNoResult, .geocodeFoundPartialResult:
                return "Couldn’t find that place. Try a different name or set lat/long."
            case .geocodeCanceled:
                return ""   // superseded by a newer request; stay quiet
            default:
                break
            }
        }
        return "Location lookup failed. Try again, or set lat/long below."
    }

    /// Build a compact "City, Country" label from a placemark.
    private static func placeName(_ p: CLPlacemark, fallback: String) -> String {
        let primary = p.locality ?? p.name ?? p.administrativeArea
        let parts = [primary, p.country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? fallback : parts.joined(separator: ", ")
    }

    var hasLocation: Bool { Settings.shared.hasValidLocation }

    /// Front-row location label: the resolved place name when known, else the
    /// coordinate summary, else a prompt.
    var locationDisplay: String {
        if let name = Settings.shared.locationName, !name.isEmpty { return name }
        return locationSummary
    }

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
