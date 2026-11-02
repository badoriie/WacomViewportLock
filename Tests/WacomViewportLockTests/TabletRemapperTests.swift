import CoreGraphics
import Testing

@testable import WacomViewportLock

@Suite("Overlay mapping")
struct OverlayMappingTests {
    private func remapper(source: CGRect, target: CGRect) -> TabletRemapper {
        let remapper = TabletRemapper()
        remapper.sourceRect = source
        remapper.targetRect = target
        return remapper
    }

    @Test("Corners and center of the monitor map onto the overlay")
    func mapsCornersAndCenter() throws {
        let r = remapper(
            source: CGRect(x: 0, y: 0, width: 1000, height: 500),
            target: CGRect(x: 100, y: 200, width: 401, height: 201))
        #expect(try #require(r.map(CGPoint(x: 0, y: 0))) == CGPoint(x: 100, y: 200))
        #expect(try #require(r.map(CGPoint(x: 1000, y: 500))) == CGPoint(x: 500, y: 400))
        #expect(try #require(r.map(CGPoint(x: 500, y: 250))) == CGPoint(x: 300, y: 300))
    }

    @Test("Points outside the monitor are clamped to the overlay edges")
    func clampsOutsidePoints() throws {
        let r = remapper(
            source: CGRect(x: 0, y: 0, width: 1000, height: 500),
            target: CGRect(x: 100, y: 200, width: 401, height: 201))
        #expect(try #require(r.map(CGPoint(x: -50, y: 9_999))) == CGPoint(x: 100, y: 400))
    }

    @Test("Monitors with negative origins (left of / above the main display) map correctly")
    func handlesNegativeOrigins() throws {
        let r = remapper(
            source: CGRect(x: -2560, y: -1022, width: 2560, height: 1440),
            target: CGRect(x: 0, y: 0, width: 201, height: 101))
        #expect(try #require(r.map(CGPoint(x: -1280, y: -302))) == CGPoint(x: 100, y: 50))
    }

    @Test("No mapping until both rects are known")
    func requiresRects() {
        let r = remapper(source: CGRect(x: 0, y: 0, width: 100, height: 100), target: .null)
        #expect(r.map(CGPoint(x: 10, y: 10)) == nil)
        let empty = remapper(source: .zero, target: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(empty.map(CGPoint(x: 10, y: 10)) == nil)
    }
}

@Suite("Mouse-mode clamping")
struct DisplayClampTests {
    /// MacBook display plus an external monitor up and to the left, as on the author's desk.
    let displays = [
        CGRect(x: 0, y: 0, width: 1512, height: 982),
        CGRect(x: -2560, y: -1022, width: 2560, height: 1440),
    ]

    @Test("Points on a display are unchanged")
    func keepsPointsOnScreen() {
        let point = CGPoint(x: -1000, y: 0)
        #expect(TabletRemapper.clamp(point, toNearestOf: displays) == point)
    }

    @Test("Points in the gap between displays go to the nearest display, not the bounding box")
    func clampsIntoNearestDisplay() {
        // Inside the union's bounding box but on neither display; the MacBook display is closest.
        #expect(TabletRemapper.clamp(CGPoint(x: -100, y: 600), toNearestOf: displays) == CGPoint(x: 0, y: 600))
    }

    @Test("Points past the outer edge stop at the last pixel")
    func clampsPastOuterEdge() {
        #expect(TabletRemapper.clamp(CGPoint(x: 5000, y: 100), toNearestOf: displays) == CGPoint(x: 1511, y: 100))
    }
}
