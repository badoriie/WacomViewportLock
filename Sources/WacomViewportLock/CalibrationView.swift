import AppKit
import SwiftUI

/// Settings popover: tablet dimensions, driver mapping target, and appearance.
struct CalibrationView: View {
    @Bindable var settings: AppSettings
    let viewport: ViewportController
    var onDone: () -> Void

    @State private var statusMessage: String?
    @State private var measuredWidth: Double?

    private struct DisplayOption: Identifiable {
        let id: CGDirectDisplayID
        let name: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tablet Calibration")
                .font(.headline)

            GroupBox("Active Area") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Preset", selection: presetBinding) {
                        Text("Custom").tag(TabletPreset?.none)
                        ForEach(TabletPreset.all) { preset in
                            Text(preset.name).tag(TabletPreset?.some(preset))
                        }
                    }

                    HStack {
                        TextField("Width", value: dimension(\.tabletWidthMM), format: .number.precision(.fractionLength(0...2)))
                        Text("×")
                        TextField("Height", value: dimension(\.tabletHeightMM), format: .number.precision(.fractionLength(0...2)))
                        Picker("Unit", selection: $settings.unit) {
                            ForEach(MeasurementUnit.allCases) { unit in
                                Text(unit.symbol).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .textFieldStyle(.roundedBorder)

                    LabeledContent("Aspect ratio", value: String(format: "%.3f : 1", settings.aspectRatio))
                        .foregroundStyle(.secondary)

                    Toggle("Keep overlay at physical size (1:1)", isOn: $settings.keepsPhysicalSize)
                }
                .padding(4)
            }

            GroupBox("Screen Calibration") {
                VStack(alignment: .leading, spacing: 8) {
                    if let scale = viewport.currentScreenScale {
                        Text(
                            "\(scale.screenName): \(scale.pointsPerMM, format: .number.precision(.fractionLength(3))) pt/mm (\(scale.isCalibrated ? "measured" : "reported by the display"))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Text(
                        "For an exact size, measure the overlay's width on screen with a ruler (outer edge of the blue border) and enter it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("Measured width", value: $measuredWidth, format: .number.precision(.fractionLength(0...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Text(settings.unit.symbol)
                        Button("Apply", action: applyMeasurement)
                            .disabled((measuredWidth ?? 0) <= 0)
                        Spacer()
                        Button("Reset") {
                            viewport.resetScreenCalibration()
                            statusMessage = "Using the size reported by the display."
                        }
                        .disabled(viewport.currentScreenScale?.isCalibrated != true)
                    }
                }
                .padding(4)
            }

            GroupBox("Tablet Mapping") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Tablet mapped to", selection: mappedDisplay) {
                        ForEach(displayOptions) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    Label(
                        "Choose the same monitor here and in Wacom Tablet Properties › Mapping, and keep the overlay on that monitor.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            }

            GroupBox("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ColorPicker("Color", selection: overlayColor, supportsOpacity: false)
                        Spacer()
                        Button("Reset") {
                            settings.overlayColor = AppSettings.defaultOverlayColor
                        }
                    }
                    HStack {
                        Slider(value: $settings.opacity, in: AppSettings.opacityRange) {
                            Text("Opacity")
                        }
                        Text("\(Int((settings.opacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .padding(4)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !settings.keepsPhysicalSize {
                    Button("Match Physical Size (1:1)", action: matchPhysicalSize)
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    // MARK: Bindings

    /// Shows/edits a millimetre value in the currently selected unit.
    private func dimension(_ keyPath: ReferenceWritableKeyPath<AppSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] / settings.unit.millimetersPerUnit },
            set: { settings[keyPath: keyPath] = max(AppSettings.minimumDimensionMM, $0 * settings.unit.millimetersPerUnit) }
        )
    }

    private var presetBinding: Binding<TabletPreset?> {
        Binding(
            get: {
                // Prefer the remembered preset; several models share the same dimensions.
                let matching = TabletPreset.all.filter {
                    abs($0.widthMM - settings.tabletWidthMM) < 0.05 && abs($0.heightMM - settings.tabletHeightMM) < 0.05
                }
                return matching.first { $0.name == settings.presetName } ?? matching.first
            },
            set: { preset in
                guard let preset else { return }
                settings.presetName = preset.name
                settings.tabletWidthMM = preset.widthMM
                settings.tabletHeightMM = preset.heightMM
            }
        )
    }

    private var overlayColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.overlayColor) },
            set: { settings.overlayColor = NSColor($0) }
        )
    }

    private var mappedDisplay: Binding<CGDirectDisplayID> {
        Binding(
            get: { viewport.mappedDisplayID },
            set: { settings.mappedDisplayID = $0 }
        )
    }

    private var displayOptions: [DisplayOption] {
        NSScreen.screens.compactMap { screen in
            screen.displayID.map { DisplayOption(id: $0, name: screen.localizedName) }
        }
    }

    // MARK: Actions

    private func applyMeasurement() {
        guard let measuredWidth, measuredWidth > 0 else { return }
        if viewport.calibrateScreen(measuredWidthMM: measuredWidth * settings.unit.millimetersPerUnit) {
            statusMessage =
                "Screen calibrated. The overlay should now measure \((settings.tabletWidthMM / settings.unit.millimetersPerUnit).formatted()) \(settings.unit.symbol) wide."
            self.measuredWidth = nil
        } else {
            statusMessage = "Couldn't calibrate this display."
        }
    }

    private func matchPhysicalSize() {
        switch viewport.matchPhysicalSize() {
        case .exact:
            statusMessage = "Overlay resized to the tablet's physical size."
        case .scaledToFit(let scale):
            statusMessage = "Scaled to \(Int((scale * 100).rounded()))% of physical size to fit the screen."
        case .unavailable:
            statusMessage = "This display doesn't report its physical size."
        }
    }
}
