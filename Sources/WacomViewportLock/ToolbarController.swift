import AppKit

/// Floating panel that never becomes key or activates the app, so clicking it
/// leaves keyboard focus with the note app underneath.
final class ToolbarPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Buttons in a non-activating panel must react to the very first click (or pen tap).
private final class ToolbarButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The lock button shown inside the top-right corner of the overlay.
/// It sits inside the overlay so the pen can reach it while the viewport is locked.
@MainActor
final class ToolbarController: NSObject {
    var onToggleLock: (() -> Void)?

    private let panel = ToolbarPanel()
    private let background = NSVisualEffectView()
    private var lockButton: NSButton!
    private weak var parentWindow: NSWindow?

    private static let inset: CGFloat = 6

    override init() {
        super.init()
        buildContent()
    }

    // MARK: Layout

    private func buildContent() {
        lockButton = makeButton(symbol: "lock.open.fill", label: "Lock", action: #selector(toggleLock))

        let stack = NSStackView(views: [lockButton])
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1.5

        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        panel.setContentSize(background.fittingSize)
    }

    private func symbol(_ name: String, _ label: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: label) ?? NSImage()
    }

    private func makeButton(symbol name: String, label: String, action: Selector) -> NSButton {
        let button = ToolbarButton(image: symbol(name, label), target: self, action: action)
        button.bezelStyle = .accessoryBarAction
        button.toolTip = label
        return button
    }

    // MARK: Visibility and position

    /// Shows the toolbar attached to `window` so it moves along with it.
    func attach(to window: NSWindow) {
        if parentWindow !== window {
            detach()
            window.addChildWindow(panel, ordered: .above)
            parentWindow = window
        }
        reposition()
        panel.orderFront(nil)
    }

    func detach() {
        parentWindow?.removeChildWindow(panel)
        parentWindow = nil
        panel.orderOut(nil)
    }

    /// Places the button just inside the top-right corner of the parent window.
    func reposition() {
        guard let parent = parentWindow else { return }
        panel.setFrameOrigin(
            NSPoint(
                x: parent.frame.maxX - panel.frame.width - Self.inset,
                y: parent.frame.maxY - panel.frame.height - Self.inset
            ))
    }

    func update(isLocked: Bool, tint: NSColor) {
        lockButton.image = symbol(isLocked ? "lock.fill" : "lock.open.fill", isLocked ? "Unlock" : "Lock")
        lockButton.toolTip = isLocked ? "Unlock (⌃⌥⌘L)" : "Lock (⌃⌥⌘L)"
        lockButton.contentTintColor = isLocked ? tint : nil
        background.layer?.borderColor = tint.cgColor
    }

    // MARK: Actions

    @objc private func toggleLock() { onToggleLock?() }
}
