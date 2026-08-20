import Testing
import Foundation
import ColorFilterEngine

/// Characterization of NOAA sunrise/sunset math and ON/OFF decisions.
///
/// Event times are asserted within `timeTolerance` of values produced by this
/// implementation on 2026-08-20. The important invariants are the
/// `+ longitude / 360.0` day selection (east/west of the UTC date line) and
/// polar day/night classification.
@Suite struct SolarSchedulerTests {
    /// Deterministic solar math should land well inside two seconds.
    let timeTolerance: TimeInterval = 2

    @Test func lisbonSummerSunriseSunset() {
        let now = isoDate("2026-08-20T12:00:00Z")
        let sun = Solar.compute(latitude: 38.7223, longitude: -9.1393, date: now)
        #expect(sun.kind == .normal)
        assertTime(sun.sunrise, equals: 1_787_205_288.60531, "Lisbon sunrise")
        assertTime(sun.sunset, equals: 1_787_253_933.45729, "Lisbon sunset")
    }

    @Test func lisbonDecisionBothSidesOfSunriseAndSunset() throws {
        let lat = 38.7223, lon = -9.1393
        let noon = isoDate("2026-08-20T12:00:00Z")
        let sun = Solar.compute(latitude: lat, longitude: lon, date: noon)
        let sunrise = try #require(sun.sunrise)
        let sunset = try #require(sun.sunset)

        let beforeSunrise = Scheduler.decide(latitude: lat, longitude: lon,
                                             now: sunrise.addingTimeInterval(-60))
        #expect(beforeSunrise.wantOn)
        #expect(beforeSunrise.reason == "before sunrise — dark")

        let afterSunrise = Scheduler.decide(latitude: lat, longitude: lon,
                                            now: sunrise.addingTimeInterval(60))
        #expect(!afterSunrise.wantOn)
        #expect(afterSunrise.reason == "between sunrise and sunset — light")

        let beforeSunset = Scheduler.decide(latitude: lat, longitude: lon,
                                            now: sunset.addingTimeInterval(-60))
        #expect(!beforeSunset.wantOn)

        let afterSunset = Scheduler.decide(latitude: lat, longitude: lon,
                                           now: sunset.addingTimeInterval(60))
        #expect(afterSunset.wantOn)
        #expect(afterSunset.reason == "after sunset — dark")
    }

    @Test func shanghaiNearUTCMidnightUsesLongitudeLocalDay() throws {
        // 00:10 UTC 20 Aug is already morning of 20 Aug in Shanghai (UTC+8).
        // Without +longitude/360 this picks the previous local day's sunrise.
        let now = isoDate("2026-08-20T00:10:00Z")
        let sun = Solar.compute(latitude: 31.2304, longitude: 121.4737, date: now)
        #expect(sun.kind == .normal)
        assertTime(sun.sunrise, equals: 1_787_174_555.85811, "Shanghai sunrise")
        assertTime(sun.sunset, equals: 1_787_221_981.84572, "Shanghai sunset")
        let rise = try #require(sun.sunrise)
        let set = try #require(sun.sunset)
        #expect(rise < now)
        #expect(now < set)

        let d = Scheduler.decide(latitude: 31.2304, longitude: 121.4737, now: now)
        #expect(!d.wantOn, "Shanghai local morning should be light")
    }

    @Test func brisbaneNearUTCDayBoundary() {
        let now = isoDate("2026-08-20T00:10:00Z")
        let sun = Solar.compute(latitude: -27.4698, longitude: 153.0251, date: now)
        #expect(sun.kind == .normal)
        assertTime(sun.sunrise, equals: 1_787_170_472.03958, "Brisbane sunrise")
        assertTime(sun.sunset, equals: 1_787_210_923.35853, "Brisbane sunset")
    }

    @Test func westernLongitudeLateUTC() {
        let now = isoDate("2026-08-20T23:50:00Z")
        let sun = Solar.compute(latitude: 37.7749, longitude: -122.4194, date: now)
        #expect(sun.kind == .normal)
        assertTime(sun.sunrise, equals: 1_787_232_578.90842, "SF sunrise")
        assertTime(sun.sunset, equals: 1_787_281_008.92101, "SF sunset")
        let d = Scheduler.decide(latitude: 37.7749, longitude: -122.4194, now: now)
        // 23:50 UTC 20 Aug is 16:50 PDT — after sunrise, before sunset.
        #expect(!d.wantOn, "SF 16:50 local is daylight")
    }

    @Test func polarDayAndNight() {
        let june = isoDate("2026-06-21T12:00:00Z")
        let dec = isoDate("2026-12-21T12:00:00Z")
        let day = Solar.compute(latitude: 78.22, longitude: 15.63, date: june)
        let night = Solar.compute(latitude: 78.22, longitude: 15.63, date: dec)
        #expect(day.kind == .polarDay)
        #expect(day.sunrise == nil)
        #expect(day.sunset == nil)
        #expect(night.kind == .polarNight)

        let dayD = Scheduler.decide(latitude: 78.22, longitude: 15.63, now: june)
        #expect(!dayD.wantOn)
        #expect(dayD.reason.contains("polar day"))

        let nightD = Scheduler.decide(latitude: 78.22, longitude: 15.63, now: dec)
        #expect(nightD.wantOn)
        #expect(nightD.reason.contains("polar night"))
    }

    @Test func zeroOffsetsMatchDefault() {
        let now = isoDate("2026-08-20T12:00:00Z")
        let a = Scheduler.decide(latitude: 38.7223, longitude: -9.1393, now: now)
        let b = Scheduler.decide(latitude: 38.7223, longitude: -9.1393,
                                 sunriseOffsetMinutes: 0, sunsetOffsetMinutes: 0, now: now)
        #expect(a.wantOn == b.wantOn)
        #expect(a.adjustedSunrise == b.adjustedSunrise)
        #expect(a.adjustedSunset == b.adjustedSunset)
    }

    @Test func positiveSunriseOffsetKeepsFilterOnAfterAstronomicalSunrise() throws {
        let lat = 38.7223, lon = -9.1393
        let noon = isoDate("2026-08-20T12:00:00Z")
        let sunrise = try #require(Solar.compute(latitude: lat, longitude: lon, date: noon).sunrise)
        let tenAfter = sunrise.addingTimeInterval(10 * 60)
        #expect(!Scheduler.decide(latitude: lat, longitude: lon, now: tenAfter).wantOn)
        let delayed = Scheduler.decide(latitude: lat, longitude: lon,
                                       sunriseOffsetMinutes: 30, now: tenAfter)
        #expect(delayed.wantOn)
        #expect(delayed.adjustedSunrise == sunrise.addingTimeInterval(30 * 60))
    }

    @Test func negativeSunsetOffsetTurnsFilterOnBeforeAstronomicalSunset() throws {
        let lat = 38.7223, lon = -9.1393
        let noon = isoDate("2026-08-20T12:00:00Z")
        let sunset = try #require(Solar.compute(latitude: lat, longitude: lon, date: noon).sunset)
        let tenBefore = sunset.addingTimeInterval(-10 * 60)
        #expect(!Scheduler.decide(latitude: lat, longitude: lon, now: tenBefore).wantOn)
        let early = Scheduler.decide(latitude: lat, longitude: lon,
                                     sunsetOffsetMinutes: -30, now: tenBefore)
        #expect(early.wantOn)
    }

    private func assertTime(_ date: Date?, equals unix: TimeInterval, _ label: String) {
        guard let date else {
            Issue.record("\(label) missing")
            return
        }
        let delta = abs(date.timeIntervalSince1970 - unix)
        #expect(delta <= timeTolerance, "\(label) off by \(date.timeIntervalSince1970 - unix)s")
    }
}
