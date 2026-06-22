// Generates the md-fire app icon: a deep-black squircle with a flame glowing in the cyan→violet
// brand gradient. Run:  swift scripts/gen-icon.swift
// Writes icon_*.png into Resources/Assets.xcassets/AppIcon.appiconset.
import AppKit

let outDir = "Resources/Assets.xcassets/AppIcon.appiconset"
let sizes: [(String, Int)] = [
    ("icon_16", 16), ("icon_32", 32), ("icon_64", 64),
    ("icon_128", 128), ("icon_256", 256), ("icon_512", 512), ("icon_1024", 1024),
]

let cyan = NSColor(srgbRed: 0.082, green: 0.741, blue: 0.925, alpha: 1)   // #15BDEC brand accent
let violet = NSColor(srgbRed: 0.553, green: 0.357, blue: 0.965, alpha: 1) // brand violet

/// A cyan→violet flame at the given pixel size, transparent outside the flame.
func gradientFlame(_ side: CGFloat) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: side, weight: .black)
    let symbol = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(cfg)!
    let size = symbol.size
    let image = NSImage(size: size)
    image.lockFocus()
    NSGradient(colors: [cyan, violet])!.draw(in: NSRect(origin: .zero, size: size), angle: -65)
    symbol.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .destinationIn, fraction: 1)
    image.unlockFocus()
    return image
}

func makeIcon(_ n: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: n, height: n)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let full = NSRect(x: 0, y: 0, width: n, height: n)

    // Squircle shape (transparent corners), filled with a near-black vertical gradient.
    let radius = CGFloat(n) * 0.2237
    let squircle = NSBezierPath(roundedRect: full, xRadius: radius, yRadius: radius)
    squircle.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.14, green: 0.14, blue: 0.15, alpha: 1),
                        NSColor(srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1)])!
        .draw(in: full, angle: -90)

    // A faint top sheen for depth.
    NSGradient(colors: [NSColor(white: 1, alpha: 0.06), NSColor(white: 1, alpha: 0)])!
        .draw(in: full, angle: -90)

    // The glowing flame, centered.
    let flameSide = CGFloat(n) * 0.62
    let flame = gradientFlame(flameSide)
    let fs = flame.size
    let rect = NSRect(x: (CGFloat(n) - fs.width) / 2, y: (CGFloat(n) - fs.height) / 2,
                      width: fs.width, height: fs.height)
    ctx.setShadow(offset: .zero, blur: CGFloat(n) * 0.05,
                  color: NSColor(srgbRed: 0.16, green: 0.66, blue: 1, alpha: 0.6).cgColor)
    flame.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (name, n) in sizes {
    if let png = makeIcon(n) {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
        print("wrote \(name).png  \(n)x\(n)")
    } else {
        print("FAILED \(name)")
    }
}
