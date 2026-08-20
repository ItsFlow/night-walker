import Foundation

/// A validated WGS-84 coordinate pair. Both values must be finite and in range
/// or the pair is rejected as a whole — there is no “latitude only” location.
public struct Coordinates: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard Self.isValid(latitude: latitude, longitude: longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    public static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
    }

    /// Parse a pair of user/CLI text fields. Trims whitespace. Rejects empty,
    /// non-numeric, non-finite, and out-of-range values (including `nan`/`inf`).
    public static func parse(latitudeText: String, longitudeText: String) -> Coordinates? {
        let latText = latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lonText = longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lat = Double(latText), let lon = Double(lonText) else { return nil }
        return Coordinates(latitude: lat, longitude: lon)
    }
}

/// Finite `Double` parse used for offsets and similar numeric settings.
/// Missing/empty input is not handled here — callers map that to a default.
public enum FiniteDouble {
    public static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
}
