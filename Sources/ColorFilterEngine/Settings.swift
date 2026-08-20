import Foundation
import CoreFoundation

/// Persisted app settings, backed by UserDefaults (the app's own bundle domain).
///
/// Strength is intentionally NOT stored here — it lives in the OS Color Filters
/// preference itself (see `ColorFilters.strength`), so it already persists and
/// there's no second copy to drift out of sync.
///
/// Production uses `Settings.shared` (`UserDefaults.standard`). Tests inject an
/// isolated `UserDefaults(suiteName:)` so they never touch the live app domain.
public final class Settings {
    public static let shared = Settings()
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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
    public var automationEnabled: Bool {
        get { defaults.bool(forKey: Key.automationEnabled) }
        set { defaults.set(newValue, forKey: Key.automationEnabled) }
    }

    public var latitude: Double? {
        get { readOptionalDouble(Key.latitude) }
        set { setOptional(newValue, Key.latitude) }
    }

    public var longitude: Double? {
        get { readOptionalDouble(Key.longitude) }
        set { setOptional(newValue, Key.longitude) }
    }

    /// The only location the engine treats as usable: both coordinates parse
    /// as finite numbers and sit inside WGS-84 ranges. A missing, malformed,
    /// non-finite, or out-of-range member fails the whole pair closed.
    public var coordinates: Coordinates? {
        get {
            guard let lat = latitude, let lon = longitude else { return nil }
            return Coordinates(latitude: lat, longitude: lon)
        }
        set {
            latitude = newValue?.latitude
            longitude = newValue?.longitude
        }
    }

    /// Human-readable name of the resolved location (e.g. "Lisbon, Portugal").
    /// Set when the user geocodes a city; used only for display. The scheduling
    /// engine still runs purely off `latitude`/`longitude`.
    public var locationName: String? {
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

    /// Missing or malformed offsets mean zero, matching an unset key.
    public var sunriseOffsetMinutes: Double {
        get { readFiniteDouble(Key.sunriseOffsetMinutes) ?? 0 }
        set { defaults.set(newValue, forKey: Key.sunriseOffsetMinutes) }
    }

    public var sunsetOffsetMinutes: Double {
        get { readFiniteDouble(Key.sunsetOffsetMinutes) ?? 0 }
        set { defaults.set(newValue, forKey: Key.sunsetOffsetMinutes) }
    }

    public var hasValidLocation: Bool { coordinates != nil }

    /// Returns a finite Double if the key holds a number or a parseable numeric
    /// string. Unset keys, booleans, and junk strings (`"banana"`, `"nan"`) are
    /// nil — never coerced to 0 the way `UserDefaults.double(forKey:)` does.
    private func readOptionalDouble(_ key: String) -> Double? {
        readFiniteDouble(key)
    }

    private func readFiniteDouble(_ key: String) -> Double? {
        guard let obj = defaults.object(forKey: key) else { return nil }
        if let string = obj as? String {
            return FiniteDouble.parse(string)
        }
        if let number = obj as? NSNumber {
            // Bool bridges to NSNumber; a boolean is not a coordinate/offset.
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() { return nil }
            let value = number.doubleValue
            return value.isFinite ? value : nil
        }
        return nil
    }

    private func setOptional(_ value: Double?, _ key: String) {
        if let value = value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
