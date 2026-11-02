import AppKit
import Darwin

/// Hides and shows the system cursor, even while another app is frontmost.
///
/// `CGDisplayHideCursor` normally only works for the active app. The private window-server
/// connection property "SetsCursorInBackground" lifts that restriction; it's widely used by
/// cursor utilities but is not App Store–safe. If it's unavailable, hiding only works while
/// this app is active.
///
/// The window server reveals the cursor again whenever another app becomes frontmost, without
/// notifying us (e.g. the user drags the overlay, which activates this app, then switches to the
/// note app). So the hidden state is re-asserted on every app activation, and pen activity
/// periodically checks that the cursor really is still hidden.
@MainActor
enum SystemCursor {
    private static var isHidden = false
    private static var isSetUp = false
    private static var activationObserver: NSObjectProtocol?
    private static var lastVisibilityCheck: CFAbsoluteTime = 0
    /// Minimum interval between visibility checks during pen activity (~200 events/s).
    private static let visibilityCheckInterval: CFAbsoluteTime = 0.1

    /// Hides the cursor; safe to call on every pen event.
    static func hide() {
        if isHidden {
            reassertIfRevealed()
            return
        }
        setUp()
        CGDisplayHideCursor(CGMainDisplayID())
        isHidden = true
        lastVisibilityCheck = CFAbsoluteTimeGetCurrent()
    }

    static func show() {
        guard isHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        isHidden = false
    }

    // MARK: Re-hiding

    /// Show-then-hide resets the window server's state and hides the cursor again.
    private static func reassert() {
        guard isHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        CGDisplayHideCursor(CGMainDisplayID())
    }

    private static func reassertIfRevealed() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastVisibilityCheck >= visibilityCheckInterval else { return }
        lastVisibilityCheck = now
        if let cursorIsVisible = Private.cursorIsVisible, cursorIsVisible() != 0 {
            reassert()
        }
    }

    // MARK: Setup

    private static func setUp() {
        guard !isSetUp else { return }
        isSetUp = true

        if let defaultConnection = Private.defaultConnection, let setProperty = Private.setConnectionProperty {
            let connection = defaultConnection()
            _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { reassert() }
        }
    }

    /// Window-server functions looked up at runtime (private, or unavailable to Swift).
    private enum Private {
        typealias DefaultConnectionFunction = @convention(c) () -> Int32
        typealias SetConnectionPropertyFunction = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        typealias CursorIsVisibleFunction = @convention(c) () -> Int32

        private static let handle = dlopen(nil, RTLD_NOW)

        static let defaultConnection = symbol("_CGSDefaultConnection", as: DefaultConnectionFunction.self)
        static let setConnectionProperty = symbol("CGSSetConnectionProperty", as: SetConnectionPropertyFunction.self)
        /// `CGCursorIsVisible` still exists in CoreGraphics but is marked unavailable to Swift.
        static let cursorIsVisible = symbol("CGCursorIsVisible", as: CursorIsVisibleFunction.self)

        private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
    }
}
