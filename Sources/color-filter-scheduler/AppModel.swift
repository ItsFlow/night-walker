import SwiftUI
import Combine
import CoreLocation
import ColorFilterEngine

/// Live Color Filters read/write. Production talks to MediaAccessibility;
/// tests and `--render-panel` inject an inert copy so they never touch SPI.
struct LiveColorFilters {
    var isEnabled: () -> Bool
    var strength: () -> Double
    var setEnabled: (Bool) -> Void
    var setStrength: (Double) -> Void

    static let system = LiveColorFilters(
        isEnabled: { ColorFilters.isEnabled },
        strength: { ColorFilters.strength },
        setEnabled: { ColorFilters.setEnabled($0) },
        setStrength: { ColorFilters.strength = $0 }
    )

    static let inert = LiveColorFilters(
        isEnabled: { false },
        strength: { 0 },
        setEnabled: { _ in },
        setStrength: { _ in }
    )
}

/// City → coordinates lookup. `CLGeocoder` is wrapped so tests can complete
/// requests out of order without hitting the network.
protocol CityLookingUp: AnyObject {
    func cancel()
    func lookup(_ query: String, completion: @escaping (Result<(Coordinates, String), Error>) -> Void)
}

final class SystemCityLookup: CityLookingUp {
    private let geocoder = CLGeocoder()

    func cancel() { geocoder.cancelGeocode() }

    func lookup(_ query: String, completion: @escaping (Result<(Coordinates, String), Error>) -> Void) {
        geocoder.geocodeAddressString(query) { placemarks, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let placemark = placemarks?.first, let loc = placemark.location else {
                completion(.failure(CLError(.geocodeFoundNoResult)))
                return
            }
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            guard let coords = Coordinates(latitude: lat, longitude: lon) else {
                completion(.failure(CLError(.geocodeFoundNoResult)))
                return
            }
            let name = AppModel.placeName(placemark, fallback: query)
            completion(.success((coords, name)))
        }
    }
}

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
///    override* — the next reconcile (timer or wake, within about five minutes)
///    pulls the filter back to what the schedule wants.
final class AppModel: ObservableObject {
    /// Live master state of Color Filters (mirrors `ColorFilters.isEnabled`).
    @Published var filterOn: Bool = false
    /// Live effect intensity, 0…1 (mirrors `ColorFilters.strength`).
    @Published var strength: Double = 0
    /// Persisted master switch for solar automation.
    @Published var automationEnabled: Bool = false
    /// Editable location strings (seed the Settings fine-tune fields). Empty when unset.
    @Published var latitudeText: String = ""
    @Published var longitudeText: String = ""
    /// The city-name text the user types to geocode (primary location input).
    /// An unsubmitted draft is never the front-page location label.
    @Published var cityText: String = ""
    /// Inline feedback for the city geocode (resolved place, or an error).
    @Published var geocodeMessage: String = ""
    /// Whether the last geocode outcome was a success (drives message color).
    @Published var lastGeocodeOK: Bool = true
    /// True while a geocode request is in flight, so the UI can show progress.
    @Published var isGeocoding: Bool = false
    /// Saved location is usable for scheduling.
    @Published var hasLocation: Bool = false
    /// Front-row location label: resolved place name, else coordinates, else a prompt.
    @Published var locationDisplay: String = "Not set"
    /// Short "37.77, -122.42" style summary, or a prompt when unset.
    @Published var locationSummary: String = "Not set"

    let settings: ColorFilterEngine.Settings
    private let live: LiveColorFilters
    private let geocoder: CityLookingUp
    private let reconcile: () -> Void
    /// Incremented for every submitted lookup (and empty-query supersede).
    /// Completions whose token is no longer current must not mutate state.
    private var geocodeGeneration: UInt64 = 0

    init(settings: ColorFilterEngine.Settings = .shared,
         live: LiveColorFilters = .system,
         geocoder: CityLookingUp? = nil,
         reconcile: @escaping () -> Void = { ReconcileEngine.reconcile() }) {
        self.settings = settings
        self.live = live
        self.geocoder = geocoder ?? SystemCityLookup()
        self.reconcile = reconcile
        refresh()
        latitudeText = settings.latitude.map(AppModel.trim) ?? ""
        longitudeText = settings.longitude.map(AppModel.trim) ?? ""
        cityText = settings.locationName ?? ""
    }

    // MARK: - Front panel actions

    /// Run = turn the filter ON right now, live, so the screen visibly changes.
    func run() {
        live.setEnabled(true)
        refresh()
    }

    /// Pause = turn the filter OFF right now, live.
    func pause() {
        live.setEnabled(false)
        refresh()
    }

    func toggleRun() {
        filterOn ? pause() : run()
    }

    // MARK: - Settings actions

    func setStrength(_ value: Double) {
        live.setStrength(value)
        strength = live.strength()
    }

    /// Turn solar automation on/off. Turning it on hands control to the
    /// scheduler and reconciles immediately so the filter snaps to the schedule.
    func setAutomation(_ on: Bool) {
        settings.automationEnabled = on
        automationEnabled = on
        reconcile()
        refresh()
    }

    /// Commit the lat/lon text fields as one validated pair. Invalid input
    /// writes nothing, does not reconcile, and surfaces an inline error.
    func applyLocation() {
        guard let coords = Coordinates.parse(latitudeText: latitudeText,
                                             longitudeText: longitudeText) else {
            lastGeocodeOK = false
            geocodeMessage = "Enter a valid latitude (−90…90) and longitude (−180…180)."
            return
        }
        let previous = settings.coordinates
        settings.coordinates = coords
        if previous != coords {
            settings.locationName = nil
        }
        latitudeText = Self.trim(coords.latitude)
        longitudeText = Self.trim(coords.longitude)
        lastGeocodeOK = true
        geocodeMessage = ""
        reconcile()
        refresh()
    }

    /// Resolve the typed city name to coordinates via CoreLocation (Apple's
    /// built-in geocoder — a system framework, no third-party dependency). On
    /// success it stores the coordinates + place name, mirrors them into the
    /// fine-tune fields, and reconciles. Failures surface inline; the UI thread
    /// is never blocked (the request is async, completion on the main queue).
    func resolveCity() {
        let query = cityText.trimmingCharacters(in: .whitespacesAndNewlines)
        geocodeGeneration += 1
        let token = geocodeGeneration
        geocoder.cancel()
        guard !query.isEmpty else {
            isGeocoding = false
            lastGeocodeOK = false
            geocodeMessage = "Type a city name, e.g. Lisbon."
            return
        }
        isGeocoding = true
        lastGeocodeOK = true
        geocodeMessage = "Resolving…"
        geocoder.lookup(query) { [weak self] result in
            guard let self else { return }
            guard token == self.geocodeGeneration else { return }
            self.isGeocoding = false
            switch result {
            case .failure(let error):
                let msg = Self.friendlyGeocodeError(error)
                if msg.isEmpty { return }   // canceled; keep busy/message of current request
                self.lastGeocodeOK = false
                self.geocodeMessage = msg
            case .success(let (coords, name)):
                self.settings.coordinates = coords
                self.settings.locationName = name
                self.latitudeText = Self.trim(coords.latitude)
                self.longitudeText = Self.trim(coords.longitude)
                self.cityText = name
                self.lastGeocodeOK = true
                self.geocodeMessage = "\(name) · \(Self.trim(coords.latitude)), \(Self.trim(coords.longitude))"
                self.reconcile()
                self.refresh()
            }
        }
    }

    /// Map a CLGeocoder error to a short, human message (no network, not found…).
    static func friendlyGeocodeError(_ error: Error) -> String {
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
    static func placeName(_ p: CLPlacemark, fallback: String) -> String {
        let primary = p.locality ?? p.name ?? p.administrativeArea
        let parts = [primary, p.country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? fallback : parts.joined(separator: ", ")
    }

    // MARK: - Refresh (pull live engine state into the published properties)

    func refresh() {
        filterOn = live.isEnabled()
        strength = live.strength()
        automationEnabled = settings.automationEnabled
        hasLocation = settings.hasValidLocation
        locationSummary = Self.summary(for: settings)
        if let name = settings.locationName, !name.isEmpty {
            locationDisplay = name
        } else {
            locationDisplay = locationSummary
        }
    }

    private static func summary(for settings: ColorFilterEngine.Settings) -> String {
        guard let coords = settings.coordinates else { return "Not set" }
        return "\(trim(coords.latitude)), \(trim(coords.longitude))"
    }

    static func trim(_ v: Double) -> String { String(format: "%g", v) }
}
