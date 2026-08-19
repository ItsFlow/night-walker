import Foundation

/// Persisted app settings, backed by UserDefaults (the app's own bundle domain).
///
/// Strength is intentionally NOT stored here — it lives in the OS Color Filters
/// preference itself (see `ColorFilters.strength`), so it already persists and
/// there's no second copy to drift out of sync.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let automationEnabled = "automationEnabled"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let locationName = "locationName"
        static let sunriseOffsetMinutes = "sunriseOffsetMinutes"
        static let sunsetOffsetMinutes = "sunsetOffsetMinutes"
    }

    /// Master switch for the automatic sunset→sunrise scheduling.
    /// Defaults to OFF so a fresh install never touches the filter until the
    /// user opts in and sets a location.
    var automationEnabled: Bool {
        get { defaults.bool(forKey: Key.automationEnabled) }
        set { defaults.set(newValue, forKey: Key.automationEnabled) }
    }

    var latitude: Double? {
        get { readOptionalDouble(Key.latitude) }
        set { setOptional(newValue, Key.latitude) }
    }

    var longitude: Double? {
        get { readOptionalDouble(Key.longitude) }
        set { setOptional(newValue, Key.longitude) }
    }

    /// Human-readable name of the resolved location (e.g. "Lisbon, Portugal").
    /// Set when the user geocodes a city; used only for display. The scheduling
    /// engine still runs purely off `latitude`/`longitude`.
    var locationName: String? {
        get {
            let s = defaults.string(forKey: Key.locationName)
            return (s?.isEmpty == false) ? s : nil
        }
        set {
            if let value = newValue, !value.isEmpty {
                defaults.set(value, forKey: Key.locationName)
            } else {
                defaults.removeObject(forKey: Key.locationName)
            }
        }
    }

    var sunriseOffsetMinutes: Double {
        get { defaults.double(forKey: Key.sunriseOffsetMinutes) }
        set { defaults.set(newValue, forKey: Key.sunriseOffsetMinutes) }
    }

    var sunsetOffsetMinutes: Double {
        get { defaults.double(forKey: Key.sunsetOffsetMinutes) }
        set { defaults.set(newValue, forKey: Key.sunsetOffsetMinutes) }
    }

    var hasValidLocation: Bool {
        guard let lat = latitude, let lon = longitude else { return false }
        return lat.isFinite && lon.isFinite && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
    }

    // Returns nil if the key is unset in every domain; otherwise the value,
    // coercing string representations (e.g. from a config file or the
    // command-line argument domain) to Double.
    private func readOptionalDouble(_ key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    private func setOptional(_ value: Double?, _ key: String) {
        if let value = value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
