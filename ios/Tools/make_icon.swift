import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

let colors = [
    NSColor(srgbRed: 0.18, green: 0.18, blue: 0.18, alpha: 1).cgColor,
    NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1).cgColor,
    NSColor(srgbRed: 0.03, green: 0.03, blue: 0.03, alpha: 1).cgColor
] as CFArray
let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(size)),
    end: CGPoint(x: CGFloat(size), y: 0),
    options: []
)

let glowColors = [
    NSColor(calibratedWhite: 1, alpha: 0.10).cgColor,
    NSColor(calibratedWhite: 1, alpha: 0).cgColor
] as CFArray
let glow = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0, 1])!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 260, y: 800),
    startRadius: 0,
    endCenter: CGPoint(x: 260, y: 800),
    endRadius: 720,
    options: []
)

let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let symbolSize = symbol.size
    symbol.draw(in: NSRect(
        x: (CGFloat(size) - symbolSize.width) / 2,
        y: (CGFloat(size) - symbolSize.height) / 2 - 8,
        width: symbolSize.width,
        height: symbolSize.height
    ))
    NSGraphicsContext.restoreGraphicsState()
}

guard let image = ctx.makeImage() else { fatalError("image") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let destination = CGImageDestinationCreateWithURL(
    out as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else { fatalError("destination") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("finalize") }
print("wrote \(out.path)")
