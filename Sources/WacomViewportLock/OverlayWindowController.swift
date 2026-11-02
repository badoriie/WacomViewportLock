import AppKit

/// Frameless, transparent, always-on-top window that hosts the viewport rectangle.
final class OverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        minSize = NSSize(width: OverlayView.minimumWidth, height: 40)
    }

    // Borderless windows refuse key status by default; we need it for dragging and edge resizing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws the tinted fill, the border, and the unlocked/locked affordances, and handles
/// click-drag to move plus aspect-locked corner resizing.
final class OverlayView: NSView {
    static let borderWidth: CGFloat = 3
    static let gripSize: CGFloat = 22
    static let minimumWidth: CGFloat = 120

    var accentColor: NSColor = .systemBlue {
        didSet {
            needsDisplay = true
            penCursorLayer.fillColor = accentColor.cgColor
        }
    }
    var fillOpacity: CGFloat = 0.3 { didSet { needsDisplay = true } }
    var aspectRatio: CGFloat = 1.6
    /// When `false` (1:1 mode), the resize grip is hidden and corner drags only move the window.
    var allowsResizing = true {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    /// Shown in the hint instead of the point size, e.g. "152 × 95 mm (1:1)".
    var sizeLabel: String? { didSet { needsDisplay = true } }
    var isLocked = false {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private var resizeStart: (frame: NSRect, mouse: NSPoint)?

    /// Stand-in for the system cursor while the pen is remapped (the real one is hidden).
    private let penCursorLayer: CAShapeLayer = {
        let diameter: CGFloat = 3
        let layer = CAShapeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.path = CGPath(ellipseIn: layer.bounds, transform: nil)
        layer.isHidden = true
        layer.zPosition = 1
        return layer
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        penCursorLayer.fillColor = accentColor.cgColor
        layer?.addSublayer(penCursorLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the pen-tip marker at a point in CG global coordinates, or hides it for `nil`.
    func showPenCursor(at globalPoint: CGPoint?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let globalPoint, let window else {
            penCursorLayer.isHidden = true
            return
        }
        let screenPoint = NSPoint(x: globalPoint.x, y: ScreenGeometry.primaryScreenHeight - globalPoint.y)
        penCursorLayer.position = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        penCursorLayer.isHidden = false
    }

    private var gripRect: NSRect {
        NSRect(x: bounds.maxX - Self.gripSize, y: bounds.minY, width: Self.gripSize, height: Self.gripSize)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        guard !isLocked else { return }
        addCursorRect(bounds, cursor: .openHand)
        if allowsResizing {
            addCursorRect(gripRect, cursor: .crosshair)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // The fill must never be fully transparent, or clicks would fall through while unlocked.
        accentColor.withAlphaComponent(max(fillOpacity, 0.02)).setFill()
        bounds.fill()

        let inset = Self.borderWidth / 2
        let border = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
        border.lineWidth = Self.borderWidth
        accentColor.setStroke()
        border.stroke()

        if !isLocked {
            if allowsResizing { drawGrip() }
            drawHint()
        }
    }

    private func drawGrip() {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        for offset in stride(from: CGFloat(6), through: 16, by: 5) {
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: bounds.minY + offset))
        }
        NSColor.white.setStroke()
        path.stroke()
    }

    private func drawHint() {
        let size = sizeLabel ?? "\(Int(bounds.width)) × \(Int(bounds.height)) pt"
        let actions = allowsResizing ? "Drag to move · corner to resize · ⌃⌥⌘L to lock" : "Drag to move · ⌃⌥⌘L to lock"
        let text = "\(size)\n\(actions)"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        guard textSize.width + 24 < bounds.width, textSize.height + 16 < bounds.height else { return }

        let box = NSRect(
            x: bounds.midX - textSize.width / 2 - 10,
            y: bounds.midY - textSize.height / 2 - 6,
            width: textSize.width + 20,
            height: textSize.height + 12
        )
        accentColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        string.draw(in: box.insetBy(dx: 10, dy: 6))
    }

    // MARK: Mouse handling (only reached while unlocked; locked windows ignore mouse events)

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let point = convert(event.locationInWindow, from: nil)
        if allowsResizing, gripRect.contains(point) {
            resizeStart = (window.frame, NSEvent.mouseLocation)
        } else {
            resizeStart = nil
            window.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = resizeStart, aspectRatio > 0 else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - start.mouse.x
        let dy = start.mouse.y - mouse.y  // dragging down grows the window

        // Follow whichever axis the user is moving more, then derive the other from the aspect ratio.
        let width =
            abs(dx) >= abs(dy * aspectRatio)
            ? start.frame.width + dx
            : (start.frame.height + dy) * aspectRatio
        let clampedWidth = max(Self.minimumWidth, width)
        let height = clampedWidth / aspectRatio

        // Keep the top-left corner anchored.
        window.setFrame(
            NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: clampedWidth, height: height),
            display: true
        )
    }

    override func mouseUp(with event: NSEvent) {
        resizeStart = nil
    }
}

/// Owns the overlay window, keeps its aspect ratio in sync, and reports geometry changes.
@MainActor
final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    let overlayView = OverlayView()

    /// Called whenever the window moves or resizes.
    var onGeometryChange: (() -> Void)?
    /// Called when the window moves to a different display.
    var onScreenChange: (() -> Void)?

    private static let autosaveName = "WacomViewportOverlay"

    init(aspectRatio: CGFloat) {
        let window = OverlayWindow(contentRect: Self.defaultFrame(aspectRatio: aspectRatio))
        super.init(window: window)
        window.contentView = overlayView
        window.delegate = self

        // Restore the last frame, unless it's now off-screen (e.g. a monitor was unplugged).
        window.setFrameUsingName(Self.autosaveName)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.setFrame(Self.defaultFrame(aspectRatio: aspectRatio), display: false)
        }
        window.setFrameAutosaveName(Self.autosaveName)

        apply(aspectRatio: aspectRatio)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isLocked: Bool {
        get { overlayView.isLocked }
        set {
            overlayView.isLocked = newValue
            window?.ignoresMouseEvents = newValue
        }
    }

    /// Whether the user may resize the overlay; disabled in 1:1 physical-size mode.
    var isResizable: Bool {
        get { overlayView.allowsResizing }
        set {
            overlayView.allowsResizing = newValue
            if newValue {
                window?.styleMask.insert(.resizable)
            } else {
                window?.styleMask.remove(.resizable)
            }
        }
    }

    /// The pen's drawing area in CG global coordinates; `nil` while hidden.
    /// This is the whole window: the border is drawn on its outer edge, so the area keeps
    /// exactly the tablet's aspect ratio and physical size.
    var mappingRect: CGRect? {
        guard let window, window.isVisible else { return nil }
        return ScreenGeometry.cgRect(fromCocoa: window.frame)
    }

    /// Locks resizing to `aspectRatio` (width ÷ height) and reshapes the window, keeping its width and top-left corner.
    func apply(aspectRatio: CGFloat) {
        guard let window, aspectRatio.isFinite, aspectRatio > 0 else { return }
        overlayView.aspectRatio = aspectRatio
        window.contentAspectRatio = NSSize(width: aspectRatio, height: 1)

        let frame = window.frame
        let height = frame.width / aspectRatio
        guard abs(height - frame.height) > 0.5 else { return }
        window.setFrame(
            NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height),
            display: true
        )
    }

    private static func defaultFrame(aspectRatio: CGFloat) -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var width = min(visible.width * 0.5, 800)
        var height = width / aspectRatio
        if height > visible.height * 0.8 {
            height = visible.height * 0.8
            width = height * aspectRatio
        }
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        onGeometryChange?()
    }

    func windowDidResize(_ notification: Notification) {
        overlayView.needsDisplay = true
        onGeometryChange?()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        onScreenChange?()
        onGeometryChange?()
    }
}
