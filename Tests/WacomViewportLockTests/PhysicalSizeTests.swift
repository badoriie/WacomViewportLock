import AppKit
import Testing

@testable import WacomViewportLock

@Suite("Physical-size overlay frame")
struct PhysicalSizeTests {
    let ctl472 = CGSize(width: 152, height: 95)
    let visible = NSRect(x: 0, y: 0, width: 1512, height: 950)

    @Test("Fits at true size and keeps the top-left corner")
    func trueSize() {
        let (frame, fit) = ViewportController.physicalFrame(
            tabletMM: ctl472, pointsPerMM: 4,
            currentFrame: NSRect(x: 200, y: 500, width: 10, height: 10), visibleFrame: visible)
        #expect(fit == 1)
        #expect(frame == NSRect(x: 200, y: 130, width: 608, height: 380))
    }

    @Test("Is moved back on screen when the top-left corner would push it off")
    func movesOnScreen() {
        let (frame, _) = ViewportController.physicalFrame(
            tabletMM: ctl472, pointsPerMM: 4,
            currentFrame: NSRect(x: 1400, y: 100, width: 300, height: 200), visibleFrame: visible)
        #expect(frame.minX == visible.maxX - 608)
        #expect(frame.minY == 0)
    }

    @Test("Scales down to fit, keeping the tablet's aspect ratio")
    func scalesToFit() {
        let small = NSRect(x: 0, y: 0, width: 1000, height: 600)
        let (frame, fit) = ViewportController.physicalFrame(
            tabletMM: ctl472, pointsPerMM: 10,
            currentFrame: NSRect(x: 0, y: 0, width: 100, height: 100), visibleFrame: small)
        #expect(abs(fit - 600.0 / 950.0) < 1e-9)
        #expect(abs(frame.height - 600) < 1e-9)
        #expect(abs(frame.width / frame.height - 152.0 / 95.0) < 1e-9)
        #expect(small.contains(frame))
    }
}
