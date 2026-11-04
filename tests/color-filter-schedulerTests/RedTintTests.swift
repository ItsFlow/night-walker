import Testing
@testable import color_filter_scheduler

@Suite struct RedTintTests {
    @Test func freshMacGrayscaleSwitchesToRedTint() {
        let w = ColorFilters.tintWrites(currentType: 1)
        #expect(w?.type == 16)
        #expect(w?.hue == 1.0)
    }

    @Test func colourBlindnessTypesAlsoSwitch() {
        for t in [0, 2, 4, 8] { #expect(ColorFilters.tintWrites(currentType: t)?.type == 16) }
    }

    @Test func existingColorTintKeepsItsHue() {
        #expect(ColorFilters.tintWrites(currentType: 16) == nil)
    }
}
