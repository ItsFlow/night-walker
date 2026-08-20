import Foundation

/// Computed sunrise/sunset for a location and instant.
public struct SunTimes: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case normal      // sun rises and sets
        case polarDay    // sun never sets (24h daylight)
        case polarNight  // sun never rises (24h darkness)
    }
    public var kind: Kind
    public var sunrise: Date?   // nil for polar cases
    public var sunset: Date?    // nil for polar cases

    public init(kind: Kind, sunrise: Date?, sunset: Date?) {
        self.kind = kind
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

/// Pure-Swift solar position math — no network, no dependencies.
///
/// Implements the standard NOAA "sunrise equation". All results are absolute
/// `Date` instants (Julian-date based), so no local-timezone bookkeeping is
/// needed: compare the returned instants directly against `Date()`.
public enum Solar {
    private static let rad = Double.pi / 180.0
    private static let deg = 180.0 / Double.pi

    /// Compute sunrise & sunset for the calendar day nearest `date` at the
    /// given latitude/longitude (degrees, north/east positive).
    public static func compute(latitude: Double, longitude: Double, date: Date = Date()) -> SunTimes {
        // Julian date of the given instant.
        let jd = date.timeIntervalSince1970 / 86400.0 + 2440587.5

        // Current Julian day number since 2000-01-01 12:00 TT, chosen for the
        // day LOCAL to the longitude (the `+ longitude/360` term). Without it,
        // far-east/-west locations near the UTC day boundary compute the wrong
        // calendar day's sunrise/sunset. (Equivalent to the standard "sunrise
        // equation" `n = ceil(… − l_w/360)` with west-positive longitude.)
        let n = (jd - 2451545.0 + 0.0008 + longitude / 360.0).rounded()

        // Mean solar time (approx), longitude-corrected.
        let jStar = n - longitude / 360.0

        // Solar mean anomaly (degrees, normalized to 0..360).
        var m = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
        if m < 0 { m += 360 }
        let mRad = m * rad

        // Equation of the center.
        let c = 1.9148 * sin(mRad) + 0.0200 * sin(2 * mRad) + 0.0003 * sin(3 * mRad)

        // Ecliptic longitude (degrees, normalized).
        var lambda = (m + c + 180.0 + 102.9372).truncatingRemainder(dividingBy: 360)
        if lambda < 0 { lambda += 360 }
        let lambdaRad = lambda * rad

        // Solar transit (Julian date of local solar noon).
        let jTransit = 2451545.0 + jStar + 0.0053 * sin(mRad) - 0.0069 * sin(2 * lambdaRad)

        // Declination of the sun.
        let sinDec = sin(lambdaRad) * sin(23.4397 * rad)
        let cosDec = cos(asin(sinDec))

        // Hour angle for the standard sunrise/sunset altitude (-0.833°, which
        // accounts for atmospheric refraction and the solar disc radius).
        let latRad = latitude * rad
        let cosOmega = (sin(-0.833 * rad) - sin(latRad) * sinDec) / (cos(latRad) * cosDec)

        if cosOmega > 1 {
            // Sun stays below the horizon all day -> polar night (all dark).
            return SunTimes(kind: .polarNight, sunrise: nil, sunset: nil)
        }
        if cosOmega < -1 {
            // Sun stays above the horizon all day -> polar day (all light).
            return SunTimes(kind: .polarDay, sunrise: nil, sunset: nil)
        }

        let omega = acos(cosOmega) * deg  // degrees
        let jRise = jTransit - omega / 360.0
        let jSet = jTransit + omega / 360.0

        return SunTimes(
            kind: .normal,
            sunrise: dateFromJulian(jRise),
            sunset: dateFromJulian(jSet)
        )
    }

    private static func dateFromJulian(_ j: Double) -> Date {
        Date(timeIntervalSince1970: (j - 2440587.5) * 86400.0)
    }
}
