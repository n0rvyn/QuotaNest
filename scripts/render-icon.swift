import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let canvas = CGFloat(1024)
let source = NSImage(size: NSSize(width: canvas, height: canvas))
source.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
let gradient = NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.35, blue: 0.90, alpha: 1), ending: NSColor(srgbRed: 0.13, green: 0.65, blue: 0.95, alpha: 1))!
gradient.draw(in: tile, angle: 70)
let configuration = NSImage.SymbolConfiguration(pointSize: 560, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let gauge = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { fatalError("Gauge symbol unavailable") }
gauge.draw(in: NSRect(x: 232, y: 232, width: 560, height: 560))
source.unlockFocus()
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
