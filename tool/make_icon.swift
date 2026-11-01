// Renders NetPulse's app icon. Usage: swift tool/make_icon.swift <out.png> [--mac]
// iOS/Android: full-bleed square (the OS applies the mask); flatten alpha before use on iOS.
// macOS: rounded rectangle inside the standard 1024 grid with transparent margins.
import AppKit

let args = CommandLine.arguments
let out = args[1], mac = args.contains("--mac")
let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let tile = mac ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: size, height: size)
if mac {
  ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
  ctx.clip()
}
let space = CGColorSpaceCreateDeviceRGB()
let bg = CGGradient(colorsSpace: space, colors: [
  CGColor(red: 0.07, green: 0.16, blue: 0.36, alpha: 1),
  CGColor(red: 0.16, green: 0.47, blue: 0.84, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.minY), end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])

// Pulse line across the tile.
func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: tile.minX + x * tile.width, y: tile.minY + y * tile.height) }
let pts = [p(0.12, 0.5), p(0.34, 0.5), p(0.42, 0.66), p(0.52, 0.26), p(0.60, 0.58), p(0.66, 0.5), p(0.88, 0.5)]
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(tile.width * 0.055)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.addLines(between: pts)
ctx.strokePath()

// Upload accent dot at the end of the line.
let r = tile.width * 0.05
ctx.setFillColor(CGColor(red: 0.92, green: 0.41, blue: 0.20, alpha: 1))
ctx.fillEllipse(in: CGRect(x: pts.last!.x - r, y: pts.last!.y - r, width: r * 2, height: r * 2))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
