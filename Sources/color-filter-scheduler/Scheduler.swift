import Foundation

/// Turns (location, offsets, now) into a desired Color Filters on/off state.
enum Scheduler {
    /// The offset-adjusted sunrise/sunset used for the decision.
    struct Decision {
        var sun: SunTimes
        var adjustedSunrise: Date?
        var adjustedSunset: Date?
        var wantOn: Bool
        var reason: String
    }

    /// Fail-closed coordinate check at the CLI / Settings boundary. Does not
    /// change the NOAA formula; garbage in must not produce a schedule.
    static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
    }

    /// Positive `sunriseOffsetMinutes` shifts the morning OFF transition later;
    /// positive `sunsetOffsetMinutes` shifts the evening ON transition later.
    static func decide(latitude: Double,
                       longitude: Double,
                       sunriseOffsetMinutes: Double = 0,
                       sunsetOffsetMinutes: Double = 0,
                       now: Date = Date()) -> Decision {
        let sun = Solar.compute(latitude: latitude, longitude: longitude, date: now)
        let sunriseOffset = sunriseOffsetMinutes * 60
        let sunsetOffset = sunsetOffsetMinutes * 60

        switch sun.kind {
        case .polarNight:
            return Decision(sun: sun, adjustedSunrise: nil, adjustedSunset: nil,
                            wantOn: true, reason: "polar night (sun never rises) — treating as dark")
        case .polarDay:
            return Decision(sun: sun, adjustedSunrise: nil, adjustedSunset: nil,
                            wantOn: false, reason: "polar day (sun never sets) — treating as light")
        case .normal:
            let sr = sun.sunrise!.addingTimeInterval(sunriseOffset)
            let ss = sun.sunset!.addingTimeInterval(sunsetOffset)
            let dark = now < sr || now >= ss
            let reason: String
            if now < sr {
                reason = "before sunrise — dark"
            } else if now >= ss {
                reason = "after sunset — dark"
            } else {
                reason = "between sunrise and sunset — light"
            }
            return Decision(sun: sun, adjustedSunrise: sr, adjustedSunset: ss,
                            wantOn: dark, reason: reason)
        }
    }
}
