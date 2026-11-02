import AppKit

/// Coordinates the overlay window and the tablet remapper, and owns lock state.
@MainActor
@Observable
final class ViewportController {
    let settings: AppSettings
    private(set) var isLocked = false
    private(set) var isOverlayVisible = false

    @ObservationIgnored let overlay: OverlayWindowController
    @ObservationIgnored private let remapper = TabletRemapper()
    @ObservationIgnored private let toolbar = ToolbarController()
    /// Stand-in for the hidden system cursor while the pen is in mouse mode.
    @ObservationIgnored private let pointerWindow = PointerWindow()

    init(settings: AppSettings) {
        self.settings = settings
        overlay = OverlayWindowController(aspectRatio: settings.aspectRatio)
        overlay.onGeometryChange = { [weak self] in
            self?.updateMapping()
            self?.toolbar.reposition()
        }
        overlay.onScreenChange = { [weak self] in
            // Displays differ in pixel density; re-fit so the overlay stays 1:1 on the new one.
            guard let self, self.settings.keepsPhysicalSize else { return }
            self.matchPhysicalSize(animate: false)
        }
        remapper.onPenActivity = { [weak self] point in
            MainActor.assumeIsolated { self?.penActivity(at: point) }
        }
        toolbar.onToggleLock = { [weak self] in self?.toggleLock() }
        observeContinuously { [weak self] in self?.applySettings() }
        observeContinuously { [weak self] in
            guard let self else { return }
            self.toolbar.update(isLocked: self.isLocked, tint: self.settings.overlayColor)
        }
    }

    // MARK: Visibility

    func showOverlay() {
        guard let window = overlay.window else { return }
        window.orderFrontRegardless()
        toolbar.attach(to: window)
        isOverlayVisible = true
        updateMapping()
    }

    /// Stops pen remapping and restores the system cursor; call before quitting.
    func shutdown() {
        setLocked(false)
        remapper.stop()
        penActivity(at: nil)
    }

    func hideOverlay() {
        setLocked(false)
        toolbar.detach()
        overlay.window?.orderOut(nil)
        isOverlayVisible = false
    }

    func toggleOverlay() {
        isOverlayVisible ? hideOverlay() : showOverlay()
    }

    // MARK: Lock mode

    func toggleLock() {
        setLocked(!isLocked)
    }

    /// Locked: the overlay is click-through and pen input is remapped into it.
    /// Unlocked: the overlay can be moved/resized. After the first lock, the pen stays in mouse
    /// mode until the app quits, so unlocking never makes the pointer jump.
    func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }

        if locked {
            guard Permissions.isAccessibilityTrusted() else {
                Permissions.presentAccessibilityAlert()
                return
            }
            if !isOverlayVisible { showOverlay() }
            updateMapping()
            do {
                try remapper.start()
            } catch {
                presentError(error)
                return
            }
            remapper.mapping = .overlay
            overlay.isLocked = true
            isLocked = true
        } else {
            remapper.mapping = .relative
            overlay.isLocked = false
            isLocked = false
        }
        // Switch between the overlay dot and the arrow pointer without waiting for the pen to move.
        penActivity(at: remapper.penPosition)
    }

    /// While the pen is remapped, the system cursor flashes at the pen's original position
    /// before each event is remapped. Hide it and draw a stand-in instead: a pen-tip dot in the
    /// overlay while locked, an arrow pointer in mouse mode.
    private func penActivity(at point: CGPoint?) {
        guard let point else {
            SystemCursor.show()
            overlay.overlayView.showPenCursor(at: nil)
            pointerWindow.hide()
            return
        }
        SystemCursor.hide()
        if isLocked {
            pointerWindow.hide()
            overlay.overlayView.showPenCursor(at: point)
        } else {
            overlay.overlayView.showPenCursor(at: nil)
            pointerWindow.show(at: point)
        }
    }

    // MARK: Mapping

    /// The monitor the Wacom driver maps the tablet to, as chosen in Calibration.
    /// Falls back to the main display if none is chosen or the chosen one isn't connected.
    var mappedDisplayID: CGDirectDisplayID {
        let chosen = settings.mappedDisplayID
        return ScreenGeometry.activeDisplayIDs().contains(chosen) ? chosen : CGMainDisplayID()
    }

    /// Recomputes the remapper's source (driver mapping) and target (overlay) rects.
    func updateMapping() {
        remapper.sourceRect = CGDisplayBounds(mappedDisplayID)
        remapper.targetRect = overlay.mappingRect ?? .null
        remapper.displayRects = ScreenGeometry.activeDisplayIDs().map(CGDisplayBounds)
    }

    private func applySettings() {
        overlay.apply(aspectRatio: settings.aspectRatio)
        overlay.overlayView.fillOpacity = settings.opacity
        overlay.overlayView.accentColor = settings.overlayColor
        overlay.isResizable = !settings.keepsPhysicalSize
        if settings.keepsPhysicalSize {
            matchPhysicalSize(animate: false)
        } else {
            overlay.overlayView.sizeLabel = nil
        }
        _ = settings.mappedDisplayID  // track for observation; read again in updateMapping()
        updateMapping()
    }

    // MARK: Physical size

    enum PhysicalSizeResult {
        case exact
        case scaledToFit(Double)
        case unavailable
    }

    /// How many points make up one millimetre on a display.
    struct ScreenScale {
        let screenName: String
        let pointsPerMM: Double
        /// `true` if measured with a ruler, `false` if derived from the size the display reports.
        let isCalibrated: Bool
    }

    private var overlayScreen: NSScreen? {
        overlay.window?.screen ?? NSScreen.main
    }

    /// Scale of the display the overlay is currently on.
    var currentScreenScale: ScreenScale? {
        overlayScreen.flatMap(screenScale(for:))
    }

    func screenScale(for screen: NSScreen) -> ScreenScale? {
        if let key = screen.stableDisplayKey, let measured = settings.screenScaleOverrides[key], measured > 0 {
            return ScreenScale(screenName: screen.localizedName, pointsPerMM: measured, isCalibrated: true)
        }
        guard let displayID = screen.displayID else { return nil }
        let physical = CGDisplayScreenSize(displayID)  // millimetres, as reported by the display
        guard physical.width > 0 else { return nil }
        return ScreenScale(
            screenName: screen.localizedName,
            pointsPerMM: screen.frame.width / physical.width,
            isCalibrated: false
        )
    }

    /// Corrects the display's scale from a ruler measurement of the overlay's current on-screen width.
    @discardableResult
    func calibrateScreen(measuredWidthMM: Double) -> Bool {
        guard measuredWidthMM > 0,
            let window = overlay.window,
            let key = overlayScreen?.stableDisplayKey
        else { return false }
        settings.screenScaleOverrides[key] = window.frame.width / measuredWidthMM
        if !settings.keepsPhysicalSize { matchPhysicalSize() }  // 1:1 mode re-fits via observation
        return true
    }

    /// Discards the ruler measurement for the current display.
    func resetScreenCalibration() {
        guard let key = overlayScreen?.stableDisplayKey else { return }
        settings.screenScaleOverrides[key] = nil
        if !settings.keepsPhysicalSize { matchPhysicalSize() }
    }

    /// Resizes the overlay so it is the tablet's real size on its current display (true 1:1 handwriting).
    /// If that doesn't fit on screen, the overlay is scaled down, keeping the aspect ratio.
    @discardableResult
    func matchPhysicalSize(animate: Bool = true) -> PhysicalSizeResult {
        guard let window = overlay.window,
            let screen = overlayScreen,
            let scale = screenScale(for: screen)
        else {
            overlay.overlayView.sizeLabel = nil
            return .unavailable
        }

        let (frame, fit) = Self.physicalFrame(
            tabletMM: CGSize(width: settings.tabletWidthMM, height: settings.tabletHeightMM),
            pointsPerMM: scale.pointsPerMM,
            currentFrame: window.frame,
            visibleFrame: screen.visibleFrame
        )
        if !window.frame.equalTo(frame) {
            window.setFrame(frame, display: true, animate: animate)
        }

        if settings.keepsPhysicalSize {
            overlay.overlayView.sizeLabel =
                fit < 1
                ? "Scaled to \(Int((fit * 100).rounded()))% to fit this display"
                : "\(formatLength(settings.tabletWidthMM)) × \(formatLength(settings.tabletHeightMM)) \(settings.unit.symbol) (1:1)"
        }
        return fit < 1 ? .scaledToFit(fit) : .exact
    }

    /// The overlay frame at the tablet's physical size, scaled down (keeping the aspect ratio) if it
    /// doesn't fit `visibleFrame`. Keeps the top-left corner where possible, then moves the frame on screen.
    /// - Returns: The frame (AppKit coordinates) and the scale applied to fit (1 = true physical size).
    nonisolated static func physicalFrame(
        tabletMM: CGSize,
        pointsPerMM: CGFloat,
        currentFrame: NSRect,
        visibleFrame visible: NSRect
    ) -> (frame: NSRect, fit: CGFloat) {
        var size = NSSize(width: tabletMM.width * pointsPerMM, height: tabletMM.height * pointsPerMM)
        let fit = min(1, visible.width / size.width, visible.height / size.height)
        size = NSSize(width: size.width * fit, height: size.height * fit)

        var frame = NSRect(x: currentFrame.minX, y: currentFrame.maxY - size.height, width: size.width, height: size.height)
        frame.origin.x = frame.minX.clamped(to: visible.minX...(visible.maxX - size.width))
        frame.origin.y = frame.minY.clamped(to: visible.minY...(visible.maxY - size.height))
        return (frame, fit)
    }

    private func formatLength(_ millimeters: Double) -> String {
        (millimeters / settings.unit.millimetersPerUnit).formatted(.number.precision(.fractionLength(0...2)))
    }

    private func presentError(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
