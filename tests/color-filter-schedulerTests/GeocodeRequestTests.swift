import Foundation
import Testing
import CoreLocation
import ColorFilterEngine
@testable import color_filter_scheduler

private final class GeocodeHarness {
    let name: String
    let defaults: UserDefaults
    let settings: ColorFilterEngine.Settings
    let geocoder: FakeCityLookup
    let box = ReconcileBox()
    let model: AppModel
    var reconciles: Int { box.count }

    init() {
        let env = IsolatedDefaults.make()
        name = env.name
        defaults = env.defaults
        settings = env.settings
        geocoder = FakeCityLookup()
        model = AppModel(settings: settings,
                         live: .inert,
                         geocoder: geocoder,
                         reconcile: { [box] in box.count += 1 })
    }

    deinit { IsolatedDefaults.remove(name, defaults) }
}

private final class ReconcileBox { var count = 0 }

@Suite struct GeocodeRequestTests {
    @Test func emptyQueryDoesNotLookupAndSupersedesInFlight() {
        let h = GeocodeHarness()
        h.geocoder.invokeCanceledOnCancel = true
        h.model.cityText = "Lisbon"
        h.model.resolveCity()
        #expect(h.model.isGeocoding)
        #expect(h.geocoder.pending.count == 1)

        h.model.cityText = "   "
        h.model.resolveCity()
        #expect(!h.model.isGeocoding)
        #expect(h.model.geocodeMessage == "Type a city name, e.g. Lisbon.")
        #expect(!h.model.lastGeocodeOK)
        #expect(h.settings.coordinates == nil)
        #expect(h.reconciles == 0)
    }

    @Test func canceledADoesNotClearNewerBusyState() {
        let h = GeocodeHarness()
        h.model.cityText = "Lisbon"
        h.model.resolveCity()
        #expect(h.model.isGeocoding)

        h.model.cityText = "Munich"
        h.model.resolveCity()
        #expect(h.geocoder.cancelCount == 2)
        #expect(h.model.isGeocoding, "A's canceled completion must not idle the model")
        #expect(h.geocoder.pending.count == 1)
        #expect(h.geocoder.pending[0].query == "Munich")
        #expect(h.settings.locationName == nil)
        #expect(h.reconciles == 0)

        h.geocoder.succeed(lat: 48.137, lon: 11.575, name: "Munich, Germany")
        #expect(!h.model.isGeocoding)
        #expect(h.settings.locationName == "Munich, Germany")
        #expect(h.settings.coordinates?.latitude == 48.137)
        #expect(h.reconciles == 1)
        #expect(h.model.lastGeocodeOK)
    }

    @Test func staleSuccessAfterNewerRequestIsIgnored() {
        let h = GeocodeHarness()
        h.geocoder.invokeCanceledOnCancel = false
        h.model.cityText = "Lisbon"
        h.model.resolveCity()
        h.model.cityText = "Munich"
        h.model.resolveCity()
        #expect(h.geocoder.stale.count == 1)
        #expect(h.geocoder.pending[0].query == "Munich")

        h.geocoder.succeedStale(lat: 38.7223, lon: -9.1393, name: "Lisbon, Portugal")
        #expect(h.model.isGeocoding)
        #expect(h.settings.locationName == nil)
        #expect(h.reconciles == 0)

        h.geocoder.succeed(lat: 48.137, lon: 11.575, name: "Munich, Germany")
        #expect(h.settings.locationName == "Munich, Germany")
        #expect(h.reconciles == 1)
        #expect(!h.model.isGeocoding)
    }

    @Test func newerFailureSurfacesAndDoesNotKeepStaleSuccess() {
        let h = GeocodeHarness()
        h.geocoder.invokeCanceledOnCancel = false
        h.model.cityText = "Lisbon"
        h.model.resolveCity()
        h.model.cityText = "Nowhereville"
        h.model.resolveCity()
        h.geocoder.fail(CLError(.geocodeFoundNoResult))
        #expect(!h.model.isGeocoding)
        #expect(!h.model.lastGeocodeOK)
        #expect(h.settings.coordinates == nil)
        #expect(h.reconciles == 0)

        h.geocoder.succeedStale(lat: 38.7223, lon: -9.1393, name: "Lisbon, Portugal")
        #expect(h.settings.coordinates == nil)
        #expect(h.reconciles == 0)
    }

    @Test func newerSuccessPersists() {
        let h = GeocodeHarness()
        h.model.cityText = "Lisbon"
        h.model.resolveCity()
        h.geocoder.succeed(lat: 38.7223, lon: -9.1393, name: "Lisbon, Portugal")
        #expect(h.settings.locationName == "Lisbon, Portugal")
        #expect(h.model.locationDisplay == "Lisbon, Portugal")
        #expect(h.model.cityText == "Lisbon, Portugal")
        #expect(h.reconciles == 1)
        #expect(!h.model.isGeocoding)
    }
}
