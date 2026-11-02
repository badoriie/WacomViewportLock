import AppKit

/// An arrow pointer drawn in a tiny click-through window at the cursor level.
///
/// Stands in for the hidden system cursor while the pen is in mouse mode: the window server
/// would otherwise flash the real cursor at the pen's absolute position on every movement.
@MainActor
final class PointerWindow {
    private let panel: NSPanel
    private let imageSize: NSSize
    /// Offset of the arrow's tip from the image's top-left corner.
    private let hotSpot: NSPoint

    init() {
        let cursor = NSCursor.arrow
        imageSize = cursor.image.size
        hotSpot = cursor.hotSpot

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: imageSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: imageSize))
        imageView.image = cursor.image
        imageView.imageScaling = .scaleNone
        panel.contentView = imageView
    }

    /// Shows the pointer with its tip at a point in CG global coordinates.
    func show(at globalPoint: CGPoint) {
        let tipY = ScreenGeometry.primaryScreenHeight - globalPoint.y
        panel.setFrameOrigin(
            NSPoint(
                x: globalPoint.x - hotSpot.x,
                y: tipY + hotSpot.y - imageSize.height
            ))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }
}
