#!/usr/bin/env swift
// Reproducible code-drawn app icon; no external asset or runtime dependency.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let folder = root.appendingPathComponent("MacPulse/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var icons: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let shape = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 200, yRadius: 200)
        NSGradient(colors: [NSColor(red: 0.12, green: 0.25, blue: 0.26, alpha: 1),
                            NSColor(red: 0.055, green: 0.075, blue: 0.12, alpha: 1)])!.draw(in: shape, angle: -60)
        let ring = NSBezierPath(ovalIn: NSRect(x: 230, y: 230, width: 564, height: 564))
        NSColor.white.withAlphaComponent(0.08).setStroke()
        ring.lineWidth = 32
        ring.stroke()
        let pulse = NSBezierPath()
        pulse.move(to: NSPoint(x: 210, y: 500))
        for point in [NSPoint(x: 340, y: 500), NSPoint(x: 410, y: 650), NSPoint(x: 505, y: 335),
                      NSPoint(x: 605, y: 720), NSPoint(x: 680, y: 500), NSPoint(x: 815, y: 500)] {
            pulse.line(to: point)
        }
        pulse.lineWidth = 40
        pulse.lineCapStyle = .round
        pulse.lineJoinStyle = .round
        NSColor(red: 0.43, green: 0.94, blue: 0.77, alpha: 1).setStroke()
        pulse.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
        icons.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let contents: [String: Any] = ["images": icons, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: folder.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}\n".utf8)
    .write(to: folder.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Generated Mac Pulse app icon.")
