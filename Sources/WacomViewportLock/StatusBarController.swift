import AppKit
import SwiftUI

/// The menu bar icon and its dropdown menu, plus the Calibration popover.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let viewport: ViewportController
    private let settings: AppSettings
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private var lockItem: NSMenuItem!
    private var overlayItem: NSMenuItem!
    private var opacityLabelItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private let opacitySlider = NSSlider()

    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        // Semi-transient: stays open while using the color panel, closes when another app is clicked.
        popover.behavior = .semitransient
        let hosting = NSHostingController(
            rootView: CalibrationView(settings: settings, viewport: viewport) { [weak self] in
                self?.popover.performClose(nil)
            }
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        return popover
    }()

    init(viewport: ViewportController, settings: AppSettings) {
        self.viewport = viewport
        self.settings = settings
        super.init()
        buildMenu()
        statusItem.menu = menu
        observeContinuously { [weak self] in self?.refreshIcon() }
    }

    // MARK: Menu construction

    private func buildMenu() {
        menu.delegate = self

        lockItem = addItem("Lock Viewport", #selector(toggleLock), key: "l")
        lockItem.keyEquivalentModifierMask = [.control, .option, .command]
        overlayItem = addItem("Show Overlay", #selector(toggleOverlay))

        menu.addItem(.separator())

        opacityLabelItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        opacityLabelItem.isEnabled = false
        menu.addItem(opacityLabelItem)
        menu.addItem(makeOpacitySliderItem())

        menu.addItem(.separator())

        addItem("Calibration…", #selector(showCalibration), key: ",")
        addItem("Match Physical Size (1:1)", #selector(matchPhysicalSize))

        menu.addItem(.separator())

        accessibilityItem = addItem("Grant Accessibility Access…", #selector(grantAccessibility))
        addItem("Quit WacomViewportLock", #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func makeOpacitySliderItem() -> NSMenuItem {
        opacitySlider.minValue = AppSettings.opacityRange.lowerBound
        opacitySlider.maxValue = AppSettings.opacityRange.upperBound
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.frame = NSRect(x: 20, y: 4, width: 200, height: 20)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        container.addSubview(opacitySlider)
        let item = NSMenuItem()
        item.view = container
        return item
    }

    // MARK: State refresh

    func menuNeedsUpdate(_ menu: NSMenu) {
        lockItem.state = viewport.isLocked ? .on : .off
        overlayItem.state = viewport.isOverlayVisible ? .on : .off
        opacitySlider.doubleValue = settings.opacity
        updateOpacityLabel()
        accessibilityItem.isHidden = Permissions.isAccessibilityTrusted()
    }

    private func updateOpacityLabel() {
        opacityLabelItem.title = "Opacity: \(Int((settings.opacity * 100).rounded()))%"
    }

    private func refreshIcon() {
        let locked = viewport.isLocked
        let image = NSImage(
            systemSymbolName: locked ? "lock.rectangle" : "rectangle.dashed",
            accessibilityDescription: locked ? "Viewport locked" : "Viewport unlocked"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = locked ? "WacomViewportLock — Locked" : "WacomViewportLock — Unlocked"
    }

    // MARK: Actions

    @objc private func toggleLock() { viewport.toggleLock() }

    @objc private func toggleOverlay() { viewport.toggleOverlay() }

    @objc private func opacityChanged(_ sender: NSSlider) {
        settings.opacity = sender.doubleValue
        updateOpacityLabel()
    }

    @objc private func showCalibration() {
        // Let the menu finish closing before anchoring the popover to the status button.
        DispatchQueue.main.async { [self] in
            guard let button = statusItem.button else { return }
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func matchPhysicalSize() {
        if case .unavailable = viewport.matchPhysicalSize() {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Physical Size Unavailable"
            alert.informativeText = "This display doesn't report its physical dimensions."
            alert.runModal()
        }
    }

    @objc private func grantAccessibility() { Permissions.presentAccessibilityAlert() }

    @objc private func quit() { NSApp.terminate(nil) }
}
