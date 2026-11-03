import Foundation
import Testing

@testable import WacomViewportLock

@Suite("Updater")
struct UpdaterControllerTests {
    // Paths are built from the temporary directory rather than hard-coded (SonarCloud S1075).
    private let tmp = FileManager.default.temporaryDirectory
    private var app: URL { tmp.appendingPathComponent("WacomViewportLock.app") }
    private var info: [String: Any] {
        [
            "SUFeedURL": tmp.appendingPathComponent("appcast.xml").absoluteString,
            "SUPublicEDKey": "key",
        ]
    }

    @Test("A bundled app with feed and key can update")
    func bundled() {
        #expect(UpdaterController.canUpdate(bundleURL: app, info: info))
    }

    @Test("Unbundled runs (swift run) don't start Sparkle")
    func unbundled() {
        let binDir = tmp.appendingPathComponent(".build").appendingPathComponent("debug")
        #expect(!UpdaterController.canUpdate(bundleURL: binDir, info: info))
    }

    @Test("Missing or empty feed URL or public key disables updates", arguments: ["SUFeedURL", "SUPublicEDKey"])
    func missingKey(key: String) {
        var missing = info
        missing.removeValue(forKey: key)
        #expect(!UpdaterController.canUpdate(bundleURL: app, info: missing))
        var empty = info
        empty[key] = ""
        #expect(!UpdaterController.canUpdate(bundleURL: app, info: empty))
    }

    @Test("The shipped Info.plist is configured for updates")
    func shippedInfoPlist() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(UpdaterController.canUpdate(bundleURL: app, info: plist))
        let feed = try #require(plist["SUFeedURL"] as? String)
        // `latest` excludes pre-releases: only stable versions are offered as updates.
        let feedURL = try #require(URL(string: feed))
        #expect(Array(feedURL.pathComponents.suffix(4)) == ["releases", "latest", "download", "appcast.xml"])
    }
}
