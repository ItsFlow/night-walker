import Foundation
import Testing
import ColorFilterEngine
@testable import color_filter_scheduler

private final class LocationHarness {
    let name: String
    let defaults: UserDefaults
    let settings: ColorFilterEngine.Settings
    let model: AppModel

    init() {
        let env = IsolatedDefaults.make()
        name = env.name
        defaults = env.defaults
        settings = env.settings
        let box = ReconcileBox()
        model = AppModel(settings: settings,
                         live: .inert,
                         geocoder: FakeCityLookup(),
                         reconcile: { box.count += 1 })
        self.box = box
    }

    private let box: ReconcileBox
    var reconciles: Int { box.count }

    func seedLisbon() {
        settings.coordinates = Coordinates(latitude: 38.7223, longitude: -9.1393)
        settings.locationName = "Lisbon, Portugal"
        model.refresh()
    }

    deinit { IsolatedDefaults.remove(name, defaults) }
}

private final class ReconcileBox { var count = 0 }

@Suite struct LocationInputTests {
    @Test func validPlusInvalidWritesNeitherAndDoesNotReconcile() {
        let h = LocationHarness()
        h.seedLisbon()
        h.model.latitudeText = "40.4"
        h.model.longitudeText = "not-a-number"
        h.model.applyLocation()
        #expect(h.settings.latitude == 38.7223)
        #expect(h.settings.longitude == -9.1393)
        #expect(h.settings.locationName == "Lisbon, Portugal")
        #expect(h.reconciles == 0)
        #expect(!h.model.lastGeocodeOK)
        #expect(!h.model.geocodeMessage.isEmpty)
        #expect(h.model.locationDisplay == "Lisbon, Portugal")
    }

    @Test func invalidPlusValidWritesNeither() {
        let h = LocationHarness()
        h.seedLisbon()
        h.model.latitudeText = "91"
        h.model.longitudeText = "10"
        h.model.applyLocation()
        #expect(h.settings.latitude == 38.7223)
        #expect(h.settings.longitude == -9.1393)
        #expect(h.reconciles == 0)
    }

    @Test func emptyFieldsWriteNeither() {
        let h = LocationHarness()
        h.seedLisbon()
        h.model.latitudeText = ""
        h.model.longitudeText = ""
        h.model.applyLocation()
        #expect(h.settings.latitude == 38.7223)
        #expect(h.reconciles == 0)
    }

    @Test func nonFiniteRejected() {
        let h = LocationHarness()
        h.seedLisbon()
        h.model.latitudeText = "nan"
        h.model.longitudeText = "0"
        h.model.applyLocation()
        #expect(h.settings.latitude == 38.7223)
        #expect(h.reconciles == 0)
    }

    @Test func boundariesAccepted() {
        let h = LocationHarness()
        h.model.latitudeText = "90"
        h.model.longitudeText = "-180"
        h.model.applyLocation()
        #expect(h.settings.coordinates?.latitude == 90)
        #expect(h.settings.coordinates?.longitude == -180)
        #expect(h.reconciles == 1)
        #expect(h.model.lastGeocodeOK)
    }

    @Test func validNegativeLongitude() {
        let h = LocationHarness()
        h.model.latitudeText = "38.7223"
        h.model.longitudeText = "-9.1393"
        h.model.applyLocation()
        #expect(h.settings.coordinates?.longitude == -9.1393)
        #expect(h.reconciles == 1)
        #expect(h.model.hasLocation)
    }

    @Test func validPairClearsStaleCityName() {
        let h = LocationHarness()
        h.seedLisbon()
        h.model.latitudeText = "48.137"
        h.model.longitudeText = "11.575"
        h.model.applyLocation()
        #expect(h.settings.locationName == nil)
        #expect(h.settings.coordinates?.latitude == 48.137)
        #expect(h.settings.coordinates?.longitude == 11.575)
        #expect(h.model.locationDisplay != "Lisbon, Portugal")
        #expect(h.model.locationDisplay.contains("48.137"))
        #expect(h.reconciles == 1)
    }

    @Test func unsubmittedCityDraftIsNotFrontLabel() {
        let h = LocationHarness()
        h.seedLisbon()
        h.model.cityText = "Munich"
        #expect(h.model.locationDisplay == "Lisbon, Portugal")
    }

    @Test func unchangedCoordinatesKeepName() {
        let h = LocationHarness()
        h.seedLisbon()
        h.model.latitudeText = "38.7223"
        h.model.longitudeText = "-9.1393"
        h.model.applyLocation()
        #expect(h.settings.locationName == "Lisbon, Portugal")
        #expect(h.model.locationDisplay == "Lisbon, Portugal")
        #expect(h.reconciles == 1)
    }
}
