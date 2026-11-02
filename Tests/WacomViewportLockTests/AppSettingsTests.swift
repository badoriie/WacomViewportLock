import AppKit
import Testing

@testable import WacomViewportLock

@MainActor
@Suite("Settings")
struct AppSettingsTests {
    /// A throwaway defaults domain per test.
    private func makeDefaults() -> UserDefaults {
        let name = "WacomViewportLockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Fresh install uses the documented defaults")
    func defaults() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.tabletWidthMM == 216)
        #expect(settings.tabletHeightMM == 135)
        #expect(settings.opacity == 0.3)
        #expect(settings.keepsPhysicalSize)
        #expect(settings.unit == .millimeters)
        #expect(settings.aspectRatio == 1.6)
    }

    @Test("Changes persist across launches")
    func persists() throws {
        let defaults = makeDefaults()
        let first = AppSettings(defaults: defaults)
        first.tabletWidthMM = 152
        first.tabletHeightMM = 95
        first.opacity = 0.5
        first.unit = .inches
        first.keepsPhysicalSize = false
        first.mappedDisplayID = 3
        first.overlayColor = NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)
        first.screenScaleOverrides = ["30ae-61af-1": 3.75]

        let second = AppSettings(defaults: defaults)
        #expect(second.tabletWidthMM == 152)
        #expect(second.tabletHeightMM == 95)
        #expect(second.opacity == 0.5)
        #expect(second.unit == .inches)
        #expect(!second.keepsPhysicalSize)
        #expect(second.mappedDisplayID == 3)
        #expect(second.screenScaleOverrides == ["30ae-61af-1": 3.75])
        let color = try #require(second.overlayColor.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 1) < 0.001)
        #expect(abs(color.greenComponent - 0.5) < 0.001)
        #expect(abs(color.blueComponent) < 0.001)
    }

    @Test("Out-of-range stored values are corrected on load")
    func sanitizesStoredValues() {
        let defaults = makeDefaults()
        defaults.set(5.0, forKey: "opacity")
        defaults.set(0.0, forKey: "tabletWidthMM")
        defaults.set(-3.0, forKey: "tabletHeightMM")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.opacity == AppSettings.opacityRange.upperBound)
        #expect(settings.tabletWidthMM == AppSettings.minimumDimensionMM)
        #expect(settings.tabletHeightMM == AppSettings.minimumDimensionMM)
    }
}

@Suite("Units and presets")
struct UnitsAndPresetsTests {
    @Test func unitConversion() {
        #expect(MeasurementUnit.millimeters.millimetersPerUnit == 1)
        #expect(MeasurementUnit.inches.millimetersPerUnit == 25.4)
    }

    @Test("Preset names are unique and include the CTL-472")
    func presets() throws {
        let names = TabletPreset.all.map(\.name)
        #expect(Set(names).count == names.count)
        let ctl472 = try #require(TabletPreset.all.first { $0.name.contains("CTL-472") })
        #expect(ctl472.widthMM == 152)
        #expect(ctl472.heightMM == 95)
    }
}
