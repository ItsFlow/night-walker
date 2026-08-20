import Testing
@testable import color_filter_scheduler

@Suite struct CLITests {
    @Test func decideRejectsOutOfRangeLatitude() throws {
        let r = try Tool.run(["--decide", "--lat", "91", "--lon", "0"])
        #expect(r.status == 2)
        #expect(r.stderr.contains("lat"))
        #expect(!r.stdout.contains("decision:"))
    }

    @Test func decideRejectsOutOfRangeLongitude() throws {
        let r = try Tool.run(["--decide", "--lat", "0", "--lon", "181"])
        #expect(r.status == 2)
        #expect(!r.stdout.contains("decision:"))
    }

    @Test func decideRejectsNan() throws {
        let r = try Tool.run(["--decide", "--lat", "nan", "--lon", "0"])
        #expect(r.status == 2)
        #expect(!r.stdout.contains("decision:"))
    }

    @Test func decideRejectsNonFiniteOffset() throws {
        let r = try Tool.run(["--decide", "--lat", "38.7223", "--lon", "-9.1393", "--sr-off", "nan"])
        #expect(r.status == 2)
        #expect(r.stderr.contains("sr-off") || r.stderr.contains("finite"))
    }

    @Test func reconcileRejectsJunkBeforeApply() throws {
        let r = try Tool.run(["--reconcile", "--lat", "91", "--lon", "0", "--apply"])
        #expect(r.status == 2)
        #expect(!r.stdout.contains("applied:"))
    }

    @Test func setIntensityRejectsOutOfRangeAndNan() throws {
        for value in ["nan", "inf", "-0.1", "1.1", "nope"] {
            let r = try Tool.run(["--set-intensity", value])
            #expect(r.status == 2)
            #expect(r.stderr.contains("0..1") || r.stderr.contains("0…1"), "value \(value): \(r.stderr)")
        }
    }

    @Test func negativeCLICoordinatesAreAccepted() throws {
        let r = try Tool.run(["--decide", "--lat", "38.7223", "--lon", "-9.1393"])
        #expect(r.status == 0, "\(r.stderr)")
        #expect(r.stdout.contains("decision:"))
    }

    @Test func helpListsEngineCommandsAndMinusH() throws {
        let help = try Tool.run(["--help"])
        #expect(help.status == 0)
        #expect(help.stdout.contains("--engine-status"))
        #expect(help.stdout.contains("--engine-reconcile"))
        #expect(help.stdout.contains("-h"))
        #expect(help.stdout.contains("LIVE") || help.stdout.contains("live filter"))

        let short = try Tool.run(["-h"])
        #expect(short.status == 0, "-h must not fall through to the GUI")
        #expect(short.stdout.contains("--decide"))
    }

    @Test func engineStatusMalformedLatitudeFailsClosed() throws {
        let r = try Tool.run([
            "--engine-status",
            "-automationEnabled", "true",
            "-latitude", "banana",
            "-longitude", "121.47",
        ])
        #expect(r.status == 0, "\(r.stderr)")
        #expect(r.stdout.contains("hasLocation=false"))
        #expect(r.stdout.contains("decision=none"))
    }

    @Test func acceptedStrengthRejectsNonFinite() {
        #expect(ColorFilters.acceptedStrength(.nan) == nil)
        #expect(ColorFilters.acceptedStrength(.infinity) == nil)
        #expect(ColorFilters.acceptedStrength(-1) == 0)
        #expect(ColorFilters.acceptedStrength(2) == 1)
        #expect(ColorFilters.acceptedStrength(0.25) == 0.25)
    }
}
