import CMediaAccessibility

/// Thin wrapper over the MediaAccessibility "Color Filters" controls.
///
/// This flips the master on/off and adjusts the effect intensity. It never
/// changes the filter *type* — whatever the user chose in System Settings
/// (grayscale, color tint, protanopia, etc.) is preserved.
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

    /// Set the master state.
    static func setEnabled(_ on: Bool) {
        MADisplayFilterPrefSetCategoryEnabled(colorCategory, on ? 1 : 0)
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
