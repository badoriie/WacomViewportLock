import AppKit
import Carbon.HIToolbox

/// Wires together the settings model, the viewport (overlay + remapper),
/// the status bar menu, and the global hotkey.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewport: ViewportController!
    private var statusBar: StatusBarController!
    private var hotKey: GlobalHotKey?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        viewport = ViewportController(settings: settings)
        statusBar = StatusBarController(viewport: viewport, settings: settings)

        // ⌃⌥⌘L toggles lock mode from anywhere.
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ) { [weak self] in
            MainActor.assumeIsolated { self?.viewport.toggleLock() }
        }
        if hotKey == nil {
            NSLog("WacomViewportLock: could not register global hotkey ⌃⌥⌘L (already in use?)")
        }

        // Displays added/removed/rearranged: recompute source and target rects.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewport.updateMapping() }
        }

        viewport.showOverlay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave an event tap or click-through window behind.
        viewport.shutdown()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }
}
