import AppKit
import Observation

/// Unit used to display and enter tablet dimensions. Values are always stored in millimetres.
enum MeasurementUnit: String, CaseIterable, Identifiable {
    case millimeters
    case inches

    var id: String { rawValue }
    var symbol: String { self == .millimeters ? "mm" : "in" }
    var millimetersPerUnit: Double { self == .millimeters ? 1 : 25.4 }
}

/// Active-area presets for common Wacom tablets (from Wacom's spec sheets).
struct TabletPreset: Identifiable, Hashable {
    let name: String
    let widthMM: Double
    let heightMM: Double

    var id: String { name }

    static let all: [TabletPreset] = [
        TabletPreset(name: "One by Wacom S (CTL-472)", widthMM: 152, heightMM: 95),
        TabletPreset(name: "One by Wacom M (CTL-672)", widthMM: 216, heightMM: 135),
        TabletPreset(name: "Intuos S (CTL-4100)", widthMM: 152, heightMM: 95),
        TabletPreset(name: "Intuos M (CTL-6100)", widthMM: 216, heightMM: 135),
        TabletPreset(name: "Intuos Pro S (PTH-460)", widthMM: 160, heightMM: 100),
        TabletPreset(name: "Intuos Pro M (PTH-660)", widthMM: 224, heightMM: 148),
        TabletPreset(name: "Intuos Pro L (PTH-860)", widthMM: 311, heightMM: 216),
    ]
}

/// User-configurable state, persisted to `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    static let opacityRange: ClosedRange<Double> = 0.05...0.9
    static let minimumDimensionMM: Double = 1

    /// Physical width of the tablet's active area, in millimetres.
    var tabletWidthMM: Double {
        didSet { defaults.set(tabletWidthMM, forKey: Keys.tabletWidthMM) }
    }

    /// Physical height of the tablet's active area, in millimetres.
    var tabletHeightMM: Double {
        didSet { defaults.set(tabletHeightMM, forKey: Keys.tabletHeightMM) }
    }

    /// Name of the last chosen preset; disambiguates presets that share dimensions.
    var presetName: String {
        didSet { defaults.set(presetName, forKey: Keys.presetName) }
    }

    /// Keep the overlay at the tablet's real size on whichever display it's on (true 1:1).
    var keepsPhysicalSize: Bool {
        didSet { defaults.set(keepsPhysicalSize, forKey: Keys.keepsPhysicalSize) }
    }

    /// Ruler-measured screen scale (points per millimetre), keyed by `NSScreen.stableDisplayKey`.
    /// Overrides the size the display reports about itself, which is often inaccurate.
    var screenScaleOverrides: [String: Double] {
        didSet { defaults.set(screenScaleOverrides, forKey: Keys.screenScaleOverrides) }
    }

    /// Unit shown in the calibration UI.
    var unit: MeasurementUnit {
        didSet { defaults.set(unit.rawValue, forKey: Keys.unit) }
    }

    static let defaultOverlayColor = NSColor.systemBlue

    /// Color of the overlay's border and fill.
    var overlayColor: NSColor {
        didSet { defaults.set(Self.components(of: overlayColor), forKey: Keys.overlayColor) }
    }

    /// Fill opacity of the overlay (the border is always fully opaque).
    var opacity: Double {
        didSet { defaults.set(opacity, forKey: Keys.opacity) }
    }

    /// Monitor the Wacom driver maps the tablet to; must match Wacom Tablet Properties › Mapping.
    /// `0` (or a disconnected display) falls back to the main display.
    var mappedDisplayID: CGDirectDisplayID {
        didSet { defaults.set(Int(mappedDisplayID), forKey: Keys.mappedDisplayID) }
    }

    /// Width ÷ height of the tablet's active area.
    var aspectRatio: Double { tabletWidthMM / tabletHeightMM }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.tabletWidthMM: 216.0,
            Keys.tabletHeightMM: 135.0,
            Keys.unit: MeasurementUnit.millimeters.rawValue,
            Keys.opacity: 0.3,
            Keys.mappedDisplayID: 0,
            Keys.presetName: "",
            Keys.keepsPhysicalSize: true,
        ])
        tabletWidthMM = max(Self.minimumDimensionMM, defaults.double(forKey: Keys.tabletWidthMM))
        tabletHeightMM = max(Self.minimumDimensionMM, defaults.double(forKey: Keys.tabletHeightMM))
        unit = MeasurementUnit(rawValue: defaults.string(forKey: Keys.unit) ?? "") ?? .millimeters
        opacity = defaults.double(forKey: Keys.opacity).clamped(to: Self.opacityRange)
        overlayColor = Self.color(from: defaults.array(forKey: Keys.overlayColor) as? [Double]) ?? Self.defaultOverlayColor
        mappedDisplayID = CGDirectDisplayID(clamping: defaults.integer(forKey: Keys.mappedDisplayID))
        presetName = defaults.string(forKey: Keys.presetName) ?? ""
        keepsPhysicalSize = defaults.bool(forKey: Keys.keepsPhysicalSize)
        screenScaleOverrides = defaults.dictionary(forKey: Keys.screenScaleOverrides) as? [String: Double] ?? [:]
    }

    /// sRGB red, green, blue components for persistence.
    private static func components(of color: NSColor) -> [Double] {
        let rgb = color.usingColorSpace(.sRGB) ?? defaultOverlayColor.usingColorSpace(.sRGB)!
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map(Double.init)
    }

    private static func color(from components: [Double]?) -> NSColor? {
        guard let components, components.count == 3 else { return nil }
        return NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: 1)
    }

    private enum Keys {
        static let tabletWidthMM = "tabletWidthMM"
        static let tabletHeightMM = "tabletHeightMM"
        static let unit = "unit"
        static let opacity = "opacity"
        static let overlayColor = "overlayColor"
        static let mappedDisplayID = "mappedDisplayID"
        static let presetName = "presetName"
        static let keepsPhysicalSize = "keepsPhysicalSize"
        static let screenScaleOverrides = "screenScaleOverrides"
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
