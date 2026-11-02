import AppKit

/// Entry point. The app is a menu-bar-only accessory (no Dock icon, no main window).
@main
enum WacomViewportLockMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Fallback for unbundled runs (`swift run`); the bundle sets LSUIElement.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
