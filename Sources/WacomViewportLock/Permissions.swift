import AppKit
import ApplicationServices

/// Accessibility permission is required to create an event tap that modifies events.
enum Permissions {
    /// Returns whether the app is trusted. With `prompt`, macOS also adds the app to the
    /// Accessibility list and shows its one-time system prompt.
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Explains why access is needed and offers to open System Settings.
    @MainActor
    static func presentAccessibilityAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = """
            WacomViewportLock needs Accessibility permission to remap your pen input into the viewport.

            Enable it in System Settings › Privacy & Security › Accessibility, then lock the viewport again.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            _ = isAccessibilityTrusted(prompt: true)
            openAccessibilitySettings()
        }
    }
}
