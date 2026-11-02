import CoreGraphics
import Foundation
import os

enum TabletRemapperError: LocalizedError {
    case tapCreationFailed

    var errorDescription: String? {
        "Could not create the event tap. Make sure WacomViewportLock is enabled under System Settings › Privacy & Security › Accessibility."
    }
}

/// Intercepts tablet pointer events with `CGEventTap`s and rewrites their location.
///
/// Two mappings:
/// - `.overlay` (locked): the Wacom driver maps the pen's absolute position onto `sourceRect`
///   (the monitor configured in Wacom Tablet Properties). Each position is normalised against
///   `sourceRect` and scaled into `targetRect`, so the full tablet maps edge to edge onto the overlay.
/// - `.relative` (unlocked, after the first lock): mouse mode. Pen movement moves the pointer
///   relative to where it is, so unlocking never makes the pointer jump.
/// Mouse and trackpad events pass through untouched.
///
/// Every pen event the app receives must carry the rewritten position. If even one doesn't,
/// the app draws a stray line from the original point to the rewritten one. The system cursor
/// must also sit at the rewritten point, because many apps start a stroke at the cursor position.
/// To ensure that:
/// - Pen events are rewritten at the HID level and tagged.
/// - A second tap at the session level catches untagged pen events posted later by the driver.
///   It rewrites them too, and warps the cursor only if it's out of place. Warping on every event
///   would make the cursor flicker between the original and rewritten positions.
/// - Button events reuse the last rewritten point, since they may lack tablet data
///   or carry the system cursor position instead of the pen position.
///
/// The window server still draws the cursor briefly at the pen's original position before any
/// tap sees the event. `onPenActivity` lets the owner hide the system cursor and draw its own.
///
/// All state is accessed on the main thread: the taps' run-loop sources are attached to the main run loop.
final class TabletRemapper {
    enum Mapping {
        /// Absolute: the whole tablet maps onto `targetRect`.
        case overlay
        /// Mouse mode: pen movement moves the pointer relative to its current position.
        case relative
    }

    /// Screen area the tablet is mapped to by the driver, in CG global coordinates.
    var sourceRect: CGRect = .null
    /// Overlay area, in CG global coordinates.
    var targetRect: CGRect = .null
    /// Displays the pointer is kept on in `.relative` mapping, in CG global coordinates.
    var displayRects: [CGRect] = []
    var mapping: Mapping = .overlay {
        didSet {
            if mapping != oldValue { relativeAnchor = nil }
        }
    }
    /// Called with the rewritten pen position, or `nil` when the pen leaves the tablet or another pointing device is used.
    var onPenActivity: ((CGPoint?) -> Void)?

    fileprivate enum Stage {
        case hid
        case session
    }

    private var hidTap: CFMachPort?
    private var sessionTap: CFMachPort?
    private var runLoopSources: [CFRunLoopSource] = []
    /// Whether the pen is currently hovering over / touching the tablet.
    private var penInProximity = false
    /// Last rewritten pen position while the pen is in range; reused for button events.
    private var lastMappedPoint: CGPoint?
    /// Where the pen left the pointer; kept across pen lifts so mouse mode resumes from there.
    /// Cleared when another pointing device moves the cursor.
    private var lastPointerPosition: CGPoint?
    /// Mouse mode: pointer = anchor.pointer + (pen − anchor.pen).
    private var relativeAnchor: (pen: CGPoint, pointer: CGPoint)?
    private var lastPenEventTime: CFAbsoluteTime = 0
    /// In mouse mode, a pause this long re-anchors (harmless: re-anchoring never moves the pointer).
    private static let relativeReanchorGap: CFAbsoluteTime = 0.25

    private let logger = Logger(subsystem: "com.example.WacomViewportLock", category: "remapper")

    var isRunning: Bool { hidTap != nil }

    /// The pen's current rewritten position, or `nil` if the pen isn't in range.
    var penPosition: CGPoint? { penInProximity ? lastMappedPoint : nil }

    /// Written to `eventSourceUserData` on rewritten events ('WVLK').
    private static let remappedMarker: Int64 = 0x5756_4C4B

    private static let buttonEventTypes: Set<CGEventType> = [
        .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp,
    ]

    private static let eventTypes: [CGEventType] = [
        .mouseMoved,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .tabletPointer, .tabletProximity,
    ]

    func start() throws {
        guard hidTap == nil else { return }

        guard let hidTap = makeTap(at: .cghidEventTap, callback: hidTapCallback),
            let sessionTap = makeTap(at: .cgSessionEventTap, callback: sessionTapCallback)
        else {
            stop()
            throw TabletRemapperError.tapCreationFailed
        }

        // `CGWarpMouseCursorPosition` suppresses local events for 250 ms by default, which would stall the pen.
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0

        self.hidTap = hidTap
        self.sessionTap = sessionTap
        penInProximity = false
        lastMappedPoint = nil
        relativeAnchor = nil
    }

    func stop() {
        for tap in [hidTap, sessionTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        for source in runLoopSources {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        hidTap = nil
        sessionTap = nil
        runLoopSources = []
        penInProximity = false
        lastMappedPoint = nil
        lastPointerPosition = nil
        relativeAnchor = nil
    }

    deinit { stop() }

    private func makeTap(at location: CGEventTapLocation, callback: CGEventTapCallBack) -> CFMachPort? {
        let mask = Self.eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard
            let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        else { return nil }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSources.append(source)
        CGEvent.tapEnable(tap: tap, enable: true)
        return tap
    }

    // MARK: - Event handling

    fileprivate func process(type: CGEventType, event: CGEvent, at stage: Stage) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow taps; turn it back on.
            if let tap = stage == .hid ? hidTap : sessionTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        // Already rewritten at the HID level.
        if stage == .session, event.getIntegerValueField(.eventSourceUserData) == Self.remappedMarker {
            syncCursor(to: event.location)
            return Unmanaged.passUnretained(event)
        }

        let subtype = event.getIntegerValueField(.mouseEventSubtype)
        let isProximityEvent =
            type == .tabletProximity
            || subtype == Int64(CGEventMouseSubtype.tabletProximity.rawValue)
        if isProximityEvent {
            penInProximity = event.getIntegerValueField(.tabletProximityEventEnterProximity) != 0
            if !penInProximity {
                lastMappedPoint = nil
                relativeAnchor = nil
            }
        }

        let isButtonEvent = Self.buttonEventTypes.contains(type)
        let carriesTabletData =
            type == .tabletPointer
            || isProximityEvent
            || subtype == Int64(CGEventMouseSubtype.tabletPoint.rawValue)
        // Pen clicks may arrive without tablet data; while the pen is in proximity, they're still the pen's.
        guard carriesTabletData || (isButtonEvent && penInProximity) else {
            // Mouse or trackpad: it now owns the cursor position.
            lastPointerPosition = nil
            onPenActivity?(nil)
            return Unmanaged.passUnretained(event)
        }

        let original = event.location
        let mapped: CGPoint
        if isButtonEvent, let lastMappedPoint {
            mapped = lastMappedPoint
        } else if let point = mapping == .overlay ? map(original) : relativePoint(forPen: original) {
            mapped = point
        } else {
            if isProximityEvent, !penInProximity { onPenActivity?(nil) }
            return Unmanaged.passUnretained(event)
        }

        // Keep deltas consistent with the rewritten motion; some apps integrate them.
        if let lastMappedPoint, !isButtonEvent {
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64((mapped.x - lastMappedPoint.x).rounded()))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64((mapped.y - lastMappedPoint.y).rounded()))
        }
        event.location = mapped
        event.setIntegerValueField(.eventSourceUserData, value: Self.remappedMarker)
        lastPointerPosition = mapped

        if isProximityEvent, !penInProximity {
            // Leave the (soon visible) system cursor where the pen left the pointer.
            CGWarpMouseCursorPosition(mapped)
            onPenActivity?(nil)
        } else {
            lastMappedPoint = mapped
            // The window server already placed the cursor for events first seen at the session level.
            if stage == .session {
                syncCursor(to: mapped)
            }
            onPenActivity?(mapped)
        }

        logger.debug(
            """
            stage=\(stage == .hid ? "hid" : "session", privacy: .public) \
            mapping=\(self.mapping == .overlay ? "overlay" : "relative", privacy: .public) \
            type=\(type.rawValue, privacy: .public) subtype=\(subtype, privacy: .public) \
            in=(\(original.x, privacy: .public), \(original.y, privacy: .public)) \
            out=(\(mapped.x, privacy: .public), \(mapped.y, privacy: .public))
            """)
        return Unmanaged.passUnretained(event)
    }

    /// Moves the system cursor to `point` only if it isn't already there, to avoid flicker.
    private func syncCursor(to point: CGPoint) {
        guard let cursor = CGEvent(source: nil)?.location else { return }
        if abs(cursor.x - point.x) > 0.5 || abs(cursor.y - point.y) > 0.5 {
            CGWarpMouseCursorPosition(point)
        }
    }

    /// Maps a point from `sourceRect` into `targetRect`, clamped to stay inside it.
    func map(_ point: CGPoint) -> CGPoint? {
        guard !sourceRect.isNull, !sourceRect.isEmpty,
            !targetRect.isNull, !targetRect.isEmpty
        else { return nil }

        let nx = ((point.x - sourceRect.minX) / sourceRect.width).clamped(to: 0...1)
        let ny = ((point.y - sourceRect.minY) / sourceRect.height).clamped(to: 0...1)
        // Subtract one point so the far edges stay inside the rect (maxX/maxY are exclusive).
        return CGPoint(
            x: targetRect.minX + nx * (targetRect.width - 1),
            y: targetRect.minY + ny * (targetRect.height - 1)
        )
    }

    /// Mouse mode: moves the pointer by the pen's movement since it was (re)anchored.
    /// Anchoring happens when the pen comes into range or after a pause, and never moves the pointer.
    private func relativePoint(forPen pen: CGPoint) -> CGPoint {
        let now = CFAbsoluteTimeGetCurrent()
        defer { lastPenEventTime = now }

        if relativeAnchor == nil || now - lastPenEventTime > Self.relativeReanchorGap {
            let pointer = lastPointerPosition ?? CGEvent(source: nil)?.location ?? pen
            relativeAnchor = (pen, pointer)
        }
        guard let anchor = relativeAnchor else { return pen }

        let point = CGPoint(x: anchor.pointer.x + pen.x - anchor.pen.x, y: anchor.pointer.y + pen.y - anchor.pen.y)
        return Self.clamp(point, toNearestOf: displayRects)
    }

    /// Keeps a point on screen: displays rarely tile a perfect rectangle, so clamp into the nearest one.
    static func clamp(_ point: CGPoint, toNearestOf displayRects: [CGRect]) -> CGPoint {
        guard !displayRects.contains(where: { $0.contains(point) }) else { return point }
        let candidates = displayRects.map { rect in
            CGPoint(
                x: point.x.clamped(to: rect.minX...(rect.maxX - 1)),
                y: point.y.clamped(to: rect.minY...(rect.maxY - 1))
            )
        }
        return candidates.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) } ?? point
    }
}

// C-compatible tap callbacks; `userInfo` carries an unretained `TabletRemapper`.

private func hidTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<TabletRemapper>.fromOpaque(userInfo).takeUnretainedValue()
        .process(type: type, event: event, at: .hid)
}

private func sessionTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<TabletRemapper>.fromOpaque(userInfo).takeUnretainedValue()
        .process(type: type, event: event, at: .session)
}
