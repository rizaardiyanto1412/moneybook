// Draws the 1024×1024 app icon PNG with CoreGraphics. Usage: swift make-icon.swift <out.png> [--ios]
// --ios draws a full-bleed, opaque square (iOS applies its own mask).
import AppKit
import CoreGraphics

let args = CommandLine.arguments.dropFirst()
let ios = args.contains("--ios")
let out = args.first { !$0.hasPrefix("--") } ?? "icon-1024.png"
let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: (ios ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// macOS icon grid: 824 pt squircle centred in 1024 with a soft shadow.
let inset: CGFloat = ios ? 0 : 100
let tile = CGRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset)
let corner: CGFloat = ios ? 0 : 185
let tilePath = CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.28))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0xF0584E))
ctx.fillPath()
ctx.restoreGState()

// Coral gradient background.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0xFF8A6B), rgb(0xEE4D4D)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
// Subtle top sheen.
ctx.setFillColor(rgb(0xFFFFFF, 0.08))
ctx.fillEllipse(in: CGRect(x: tile.minX - 200, y: tile.midY + 60, width: tile.width + 400, height: tile.height))
ctx.restoreGState()

// The book: a white page block with a spine.
let book = CGRect(x: 292, y: 238, width: 440, height: 548)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x7A1F1F, 0.35))
ctx.addPath(CGPath(roundedRect: book, cornerWidth: 46, cornerHeight: 46, transform: nil))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// Spine band.
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: book, cornerWidth: 46, cornerHeight: 46, transform: nil))
ctx.clip()
ctx.setFillColor(rgb(0x2F6FDB))
ctx.fill(CGRect(x: book.minX, y: book.minY, width: 70, height: book.height))
ctx.restoreGState()

// Ledger lines: income blue, expense coral, total grey.
let lines: [(UInt32, CGFloat, CGFloat)] = [(0x2F6FDB, 640, 230), (0xEE4D4D, 560, 280), (0xEE4D4D, 480, 190), (0x9AA0A6, 400, 250)]
for (color, y, w) in lines {
    ctx.addPath(CGPath(roundedRect: CGRect(x: 412, y: y, width: w, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil))
    ctx.setFillColor(rgb(color))
    ctx.fillPath()
}

// Coin badge.
let coin = CGRect(x: 560, y: 196, width: 236, height: 236)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x000000, 0.25))
ctx.setFillColor(rgb(0xFFC93C))
ctx.fillEllipse(in: coin)
ctx.restoreGState()
ctx.setStrokeColor(rgb(0xE8A317))
ctx.setLineWidth(14)
ctx.strokeEllipse(in: coin.insetBy(dx: 22, dy: 22))

// "$" on the coin.
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = ns
let font = NSFont.systemFont(ofSize: 150, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 0.69, green: 0.42, blue: 0.0, alpha: 1)]
let glyph = NSAttributedString(string: "$", attributes: attrs)
let gs = glyph.size()
glyph.draw(at: CGPoint(x: coin.midX - gs.width / 2, y: coin.midY - gs.height / 2 + 4))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
