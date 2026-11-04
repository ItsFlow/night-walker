import CMediaAccessibility

/// Thin wrapper over the MediaAccessibility "Color Filters" controls.
///
/// This flips the master on/off and adjusts the effect intensity. Turning it on
/// first makes sure the filter type is Color Tint: a Mac that never opened the
/// Color Filters settings defaults to Grayscale, which turned the screen black
/// and white instead of red. A Mac already on Color Tint keeps its own hue.
enum ColorFilters {
    /// The "Color Filters" category id (the "__Color__" preference domain).
    /// Confirmed empirically: of the categories returned by
    /// MADisplayFilterPrefCopyCategoriesForCurrentPlatform() (1...5), category 1
    /// is the one whose enabled state mirrors
    /// `com.apple.mediaaccessibility "__Color__-MADisplayFilterCategoryEnabled"`.
    static let colorCategory: Int = 1

    /// Current master state of Color Filters.
    static var isEnabled: Bool {
        MADisplayFilterPrefGetCategoryEnabled(colorCategory) != 0
    }

    /// Set the master state. Turning on applies the red tint first.
    static func setEnabled(_ on: Bool) {
        if on { ensureRedTint() }
        MADisplayFilterPrefSetCategoryEnabled(colorCategory, on ? 1 : 0)
    }

    /// "Color Tint" in the System Settings filter type popup.
    static let colorTintType: Int = 16
    /// Red on the tint hue wheel (the value an untouched Mac reports).
    static let redHue: Double = 1.0
    /// Starting strength when switching a Mac onto Color Tint (macOS's own
    /// default of 0.4 is a faint pink). A Mac already on Color Tint keeps its own.
    static let startingIntensity: Double = 0.88

    /// What to write so the filter shows red: nothing if the type is already
    /// Color Tint (respect the hue and strength the user picked), else type,
    /// red hue and the starting strength.
    static func tintWrites(currentType: Int) -> (type: Int, hue: Double, intensity: Double)? {
        currentType == colorTintType ? nil : (colorTintType, redHue, startingIntensity)
    }

    /// Switch the filter to a red Color Tint if it is set to anything else.
    /// Idempotent: writes nothing when already Color Tint.
    @discardableResult
    static func ensureRedTint() -> Bool {
        guard let w = tintWrites(currentType: filterType) else { return false }
        MADisplayFilterPrefSetSingleColorHue(w.hue)
        MADisplayFilterPrefSetSingleColorIntensity(w.intensity)
        MADisplayFilterPrefSetType(colorCategory, w.type)
        return true
    }

    /// The currently-selected Color Filters filter type.
    static var filterType: Int {
        MADisplayFilterPrefGetType(colorCategory)
    }

    /// Effect strength, 0.0...1.0. This is the intensity of the single-color
    /// ("Color Tint") filter — the configured filter type on this Mac — which
    /// is the live macOS "Color Filters" intensity slider for that type.
    /// Reading/writing goes straight to the OS preference, so it also persists
    /// across launches without any extra bookkeeping.
    static var strength: Double {
        get { MADisplayFilterPrefGetSingleColorIntensity() }
        set {
            // Non-finite values are ignored so a slider glitch or CLI junk
            // cannot coerce nan→0 / inf→1 through min/max.
            guard let accepted = Self.acceptedStrength(newValue) else { return }
            MADisplayFilterPrefSetSingleColorIntensity(accepted)
        }
    }

    /// Finite values are clamped to 0...1. Non-finite input is rejected.
    static func acceptedStrength(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(1, max(0, value))
    }
}
