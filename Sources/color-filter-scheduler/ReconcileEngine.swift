import Foundation
import ColorFilterEngine

/// The scheduling engine: reconciles the live Color Filters state to what the
/// solar schedule says it should be. Pure of UI; the AppDelegate wires a timer
/// and wake-notification to `reconcile()`.
enum ReconcileEngine {
    /// A human-readable summary of a reconcile decision, for status display.
    struct Snapshot {
        var automationEnabled: Bool
        var hasLocation: Bool
        var currentlyEnabled: Bool
        var decision: Scheduler.Decision?
    }

    /// Compute (but do not apply) what should happen right now.
    static func snapshot(now: Date = Date()) -> Snapshot {
        let s = Settings.shared
        guard s.automationEnabled, let coords = s.coordinates else {
            return Snapshot(automationEnabled: s.automationEnabled,
                            hasLocation: s.hasValidLocation,
                            currentlyEnabled: ColorFilters.isEnabled,
                            decision: nil)
        }
        let decision = Scheduler.decide(latitude: coords.latitude, longitude: coords.longitude,
                                        sunriseOffsetMinutes: s.sunriseOffsetMinutes,
                                        sunsetOffsetMinutes: s.sunsetOffsetMinutes,
                                        now: now)
        return Snapshot(automationEnabled: true, hasLocation: true,
                        currentlyEnabled: ColorFilters.isEnabled, decision: decision)
    }

    /// Reconcile the live state to the desired state. Returns true if it changed
    /// anything. Does nothing (and returns false) when automation is off or no
    /// valid location is set — that's the fail-safe.
    @discardableResult
    static func reconcile(now: Date = Date()) -> Bool {
        let s = Settings.shared
        guard s.automationEnabled else { return false }
        guard let coords = s.coordinates else { return false }

        let decision = Scheduler.decide(latitude: coords.latitude, longitude: coords.longitude,
                                        sunriseOffsetMinutes: s.sunriseOffsetMinutes,
                                        sunsetOffsetMinutes: s.sunsetOffsetMinutes,
                                        now: now)
        guard ColorFilters.isEnabled != decision.wantOn else { return false }  // idempotent
        ColorFilters.setEnabled(decision.wantOn)
        return true
    }
}
