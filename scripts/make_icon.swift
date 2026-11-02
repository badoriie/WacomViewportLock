// Renders the app icon ("nib-lock": a padlock whose body holds a pen nib) and writes
// Resources/AppIcon.icns. Re-run after changing the artwork:
//   swift scripts/make_icon.swift && ./build_app.sh
import AppKit

let blue = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
let light = NSColor(white: 0.88, alpha: 1)

/// Draws the icon on a 1024 × 1024 canvas (bottom-left origin), following the macOS icon grid:
/// an 824 pt rounded tile centered with room for its drop shadow.
func drawIcon() {
    // Tile
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(srgbRed: 0.09, green: 0.11, blue: 0.16, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(
        starting: NSColor(srgbRed: 0.17, green: 0.20, blue: 0.28, alpha: 1),
        ending: NSColor(srgbRed: 0.06, green: 0.08, blue: 0.12, alpha: 1))!.draw(in: tile, angle: -90)

    // Shackle
    let shackle = NSBezierPath()
    shackle.move(to: NSPoint(x: 382, y: 540))
    shackle.line(to: NSPoint(x: 382, y: 640))
    shackle.appendArc(withCenter: NSPoint(x: 512, y: 640), radius: 130, startAngle: 180, endAngle: 0, clockwise: true)
    shackle.line(to: NSPoint(x: 642, y: 540))
    shackle.lineWidth = 62
    shackle.lineCapStyle = .round
    light.setStroke()
    shackle.stroke()

    // Lock body
    blue.setFill()
    NSBezierPath(roundedRect: NSRect(x: 292, y: 210, width: 440, height: 350), xRadius: 60, yRadius: 60).fill()

    // Pen nib
    let nib = NSBezierPath()
    nib.move(to: NSPoint(x: 512, y: 250))
    nib.curve(to: NSPoint(x: 448, y: 430), controlPoint1: NSPoint(x: 470, y: 320), controlPoint2: NSPoint(x: 448, y: 380))
    nib.line(to: NSPoint(x: 448, y: 500))
    nib.line(to: NSPoint(x: 576, y: 500))
    nib.line(to: NSPoint(x: 576, y: 430))
    nib.curve(to: NSPoint(x: 512, y: 250), controlPoint1: NSPoint(x: 576, y: 380), controlPoint2: NSPoint(x: 554, y: 320))
    NSColor.white.setFill()
    nib.fill()

    let slit = NSBezierPath()
    slit.move(to: NSPoint(x: 512, y: 262))
    slit.line(to: NSPoint(x: 512, y: 410))
    slit.lineWidth = 10
    blue.setStroke()
    slit.stroke()
    blue.setFill()
    NSBezierPath(ovalIn: NSRect(x: 494, y: 400, width: 36, height: 36)).fill()
}

/// Renders the icon directly at `pixels` × `pixels` (vector drawing scaled, not a downsampled bitmap).
func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// Looks up a command on `PATH` (iconutil ships with macOS). Set ICONUTIL to use a specific copy.
func findExecutable(_ name: String) -> URL {
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["ICONUTIL"] { return URL(fileURLWithPath: override) }
    let candidates = (environment["PATH"] ?? "").split(separator: ":").map {
        URL(fileURLWithPath: String($0)).appending(path: name)
    }
    guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
        fatalError("\(name) not found on PATH")
    }
    return found
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}

let output = root.appending(path: "Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = findExecutable("iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(output.path)")
