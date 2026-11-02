import AppKit

extension NSScreen {
    /// The Core Graphics display ID backing this screen.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Identifies the physical monitor across reboots and reconnections (display IDs can change).
    var stableDisplayKey: String? {
        guard let id = displayID else { return nil }
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }
}

/// Conversions between AppKit (bottom-left origin) and Core Graphics (top-left origin) global coordinates.
enum ScreenGeometry {
    /// Height of the primary display (the one containing the menu bar at launch), which anchors both coordinate systems.
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? CGDisplayBounds(CGMainDisplayID()).height
    }

    /// Converts a rect in AppKit global coordinates to CG global coordinates (as used by `CGEvent.location`).
    static func cgRect(fromCocoa rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
