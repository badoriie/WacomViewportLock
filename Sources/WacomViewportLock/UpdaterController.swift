import AppKit
import Sparkle

/// Sparkle auto-updates. The feed is the `appcast.xml` asset of the latest GitHub release
/// (`releases/latest` skips pre-releases, so only stable versions are offered).
@MainActor
final class UpdaterController: NSObject, SPUStandardUserDriverDelegate {
    /// Nil for unbundled runs (`swift run`): Sparkle needs a real .app with a feed URL.
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        guard Self.canUpdate(bundleURL: Bundle.main.bundleURL, info: Bundle.main.infoDictionary ?? [:]) else {
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        guard let controller else { return }
        // Accessory apps aren't frontmost, so the update window would open behind other apps.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    nonisolated static func canUpdate(bundleURL: URL, info: [String: Any]) -> Bool {
        guard bundleURL.pathExtension == "app" else { return false }
        guard let feed = info["SUFeedURL"] as? String, !feed.isEmpty else { return false }
        guard let key = info["SUPublicEDKey"] as? String, !key.isEmpty else { return false }
        return true
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Menu-bar apps have no Dock icon to badge, so Sparkle needs this to show scheduled-check
    /// reminders gently instead of logging a warning.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
