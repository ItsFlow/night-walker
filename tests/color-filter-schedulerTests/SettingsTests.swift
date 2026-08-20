import Testing
import Foundation
import ColorFilterEngine

@Suite struct SettingsTests {
    @Test func freshSuiteHasNoLocationAndAutomationOff() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        let settings = env.settings
        #expect(!settings.automationEnabled)
        #expect(!settings.hasValidLocation)
        #expect(settings.coordinates == nil)
        #expect(settings.sunriseOffsetMinutes == 0)
        #expect(settings.sunsetOffsetMinutes == 0)
    }

    @Test func numericLisbonPairIsValid() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.settings.latitude = 38.7223
        env.settings.longitude = -9.1393
        #expect(env.settings.hasValidLocation)
        #expect(env.settings.coordinates?.latitude == 38.7223)
        #expect(env.settings.coordinates?.longitude == -9.1393)
    }

    @Test func missingLongitudeFailsClosed() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.settings.latitude = 38.7223
        #expect(!env.settings.hasValidLocation)
        #expect(env.settings.coordinates == nil)
    }

    @Test func outOfRangeFailsClosed() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.settings.latitude = 91
        env.settings.longitude = 0
        #expect(!env.settings.hasValidLocation)

        env.settings.latitude = 0
        env.settings.longitude = 181
        #expect(!env.settings.hasValidLocation)
    }

    @Test func nonFiniteStoredDoubleFailsClosed() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.defaults.set(Double.nan, forKey: "latitude")
        env.defaults.set(0.0, forKey: "longitude")
        #expect(env.settings.latitude == nil)
        #expect(!env.settings.hasValidLocation)
    }

    @Test func malformedStringFailsClosedNotZero() {
        // Cocoa's double(forKey:) coerces "banana" to 0, which used to look like
        // a valid equator coordinate. Explicit parse must fail closed.
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.defaults.set("banana", forKey: "latitude")
        env.defaults.set(121.47, forKey: "longitude")
        #expect(env.settings.latitude == nil)
        #expect(!env.settings.hasValidLocation)
        #expect(env.settings.coordinates == nil)
    }

    @Test func nanStringFailsClosed() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.defaults.set("nan", forKey: "latitude")
        env.defaults.set("0", forKey: "longitude")
        #expect(!env.settings.hasValidLocation)
    }

    @Test func numericStringArgumentsParse() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.defaults.set("38.7223", forKey: "latitude")
        env.defaults.set("-9.1393", forKey: "longitude")
        #expect(env.settings.hasValidLocation)
        #expect(abs((env.settings.coordinates?.latitude ?? 0) - 38.7223) < 1e-9)
        #expect(abs((env.settings.coordinates?.longitude ?? 0) - -9.1393) < 1e-9)
    }

    @Test func malformedOffsetIsZero() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.defaults.set("nope", forKey: "sunriseOffsetMinutes")
        env.defaults.set("inf", forKey: "sunsetOffsetMinutes")
        #expect(env.settings.sunriseOffsetMinutes == 0)
        #expect(env.settings.sunsetOffsetMinutes == 0)
    }

    @Test func finiteOffsetsRoundTrip() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.settings.sunriseOffsetMinutes = -15
        env.settings.sunsetOffsetMinutes = 30
        #expect(env.settings.sunriseOffsetMinutes == -15)
        #expect(env.settings.sunsetOffsetMinutes == 30)
    }

    @Test func coordinateBoundaries() {
        #expect(Coordinates(latitude: 90, longitude: 180) != nil)
        #expect(Coordinates(latitude: -90, longitude: -180) != nil)
        #expect(Coordinates(latitude: 90.0001, longitude: 0) == nil)
        #expect(Coordinates(latitude: 0, longitude: 180.0001) == nil)
        #expect(Coordinates(latitude: .nan, longitude: 0) == nil)
        #expect(Coordinates(latitude: 0, longitude: .infinity) == nil)
        #expect(Coordinates.parse(latitudeText: " 38.7 ", longitudeText: " banana ") == nil)
        #expect(Coordinates.parse(latitudeText: "-9.1393", longitudeText: "-9.1393") != nil)
    }

    @Test func persistedKeyNamesUnchanged() {
        let env = IsolatedDefaults.make()
        defer { IsolatedDefaults.remove(env.name, env.defaults) }
        env.settings.automationEnabled = true
        env.settings.coordinates = Coordinates(latitude: 1, longitude: 2)
        env.settings.locationName = "X"
        env.settings.sunriseOffsetMinutes = 3
        env.settings.sunsetOffsetMinutes = 4
        #expect(env.defaults.object(forKey: "automationEnabled") as? Bool == true)
        #expect(env.defaults.double(forKey: "latitude") == 1)
        #expect(env.defaults.double(forKey: "longitude") == 2)
        #expect(env.defaults.string(forKey: "locationName") == "X")
        #expect(env.defaults.double(forKey: "sunriseOffsetMinutes") == 3)
        #expect(env.defaults.double(forKey: "sunsetOffsetMinutes") == 4)
    }
}
