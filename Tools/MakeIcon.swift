//
//  MakeIcon.swift
//  Relays — icon generator
//
//  Renders the whole app-icon set. Run from the repository root:
//
//      swift Tools/MakeIcon.swift Relays/Assets.xcassets/AppIcon.appiconset
//
//  The mark is the wordmark's "R", set in Inter — the same face the interface
//  uses — black on classic Bluesky blue, the app's own pair of colours.
//
//  Set `scanlines` to true to cut the letter into horizontal bars instead; the
//  routine measures each line against the real glyph outline, so the counter of
//  the R stays open and the ends step in and out.
//

import AppKit
import CoreGraphics
import CoreText

/// The interface face, loaded from the app's own resources so the icon and the
/// wordmark inside the app are cut from the same typeface.
let interURL = URL(fileURLWithPath: "Relays/Resources/Inter-SemiBold.ttf")
let hasInter = CTFontManagerRegisterFontsForURL(interURL as CFURL, .process, nil)

/// The plain letter is the mark; the scanline variant stays one flag away.
let scanlines = false

let blue = CGColor(red: 0.0, green: 0.522, blue: 1.0, alpha: 1)
let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let lightGrey = CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)

func drawIcon(size: CGFloat, background: Bool, rounded: Bool, inset: CGFloat, tinted: Bool) -> CGImage {
    let px = Int(size)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)

    let canvas = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let w = canvas.width

    if rounded {
        ctx.addPath(CGPath(roundedRect: canvas, cornerWidth: w * 0.2237,
                           cornerHeight: w * 0.2237, transform: nil))
        ctx.clip()
    }

    if background {
        ctx.setFillColor(blue)
        ctx.fill(CGRect(origin: .zero, size: CGSize(width: size, height: size)))
    }

    // On the blue ground the letter is black. The transparent variants have no
    // ground of their own, so there the letter has to carry itself in light.
    let ink: CGColor = tinted ? lightGrey : (background ? black : white)

    guard let letter = letterPath(in: canvas) else { return ctx.makeImage()! }

    // Below this size a scanline is thinner than a pixel and turns to mush.
    guard scanlines, size >= 128 else {
        ctx.setFillColor(ink)
        ctx.addPath(letter)
        ctx.fillPath()
        return ctx.makeImage()!
    }

    let bounds = letter.boundingBox
    let lines = 28
    let pitch = bounds.height / CGFloat(lines)
    let bar = pitch * 0.68

    guard let mask = coverage(of: letter, size: size) else { return ctx.makeImage()! }
    ctx.setFillColor(ink)

    for index in 0..<lines {
        let centre = bounds.maxY - (CGFloat(index) + 0.5) * pitch
        let row = Int((size - centre).rounded())          // bitmap rows run top-down
        guard row >= 0, row < px else { continue }

        // A stripe per filled run keeps the counter of the R open.
        for run in runs(in: mask, row: row, width: px) {
            // Alternating overshoot gives the ends their stepped, scanned look.
            let lead = w * (index % 3 == 0 ? 0.009 : index % 3 == 1 ? 0.004 : 0.0)
            let trail = w * (index % 4 == 0 ? 0.011 : index % 4 == 2 ? 0.006 : 0.002)
            let x = CGFloat(run.lowerBound) - lead
            let width = CGFloat(run.count) + lead + trail
            ctx.fill(CGRect(x: x, y: centre - bar / 2, width: width, height: bar))
        }
    }

    return ctx.makeImage()!
}

/// The glyph as a path, optically centred in the canvas.
func letterPath(in canvas: CGRect) -> CGPath? {
    // Inter sets wider than the monospaced face at the same point size, so the
    // optical size differs from the earlier mark.
    let points = canvas.width * (hasInter ? 0.92 : 0.80)
    let font = NSFont(name: "Inter-SemiBold", size: points)
        ?? NSFont.monospacedSystemFont(ofSize: canvas.width * 0.80, weight: .medium)
    let attributed = NSAttributedString(string: "R", attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

    guard let run = (CTLineGetGlyphRuns(line) as? [CTRun])?.first else { return nil }
    var glyph = CGGlyph()
    var position = CGPoint()
    CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
    CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)

    guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
    var transform = CGAffineTransform(
        translationX: canvas.midX - bounds.width / 2 - bounds.minX + position.x,
        y: canvas.midY - bounds.height / 2 - bounds.minY + position.y)
    return path.copy(using: &transform)
}

/// Renders the glyph to a grayscale buffer so rows can be measured.
func coverage(of path: CGPath, size: CGFloat) -> [UInt8]? {
    let px = Int(size)
    var buffer = [UInt8](repeating: 0, count: px * px)
    guard let ctx = CGContext(data: &buffer, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: px, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.addPath(path)
    ctx.fillPath()
    return buffer
}

/// Contiguous filled spans in one bitmap row.
func runs(in mask: [UInt8], row: Int, width: Int) -> [Range<Int>] {
    var spans: [Range<Int>] = []
    var start: Int?
    for x in 0..<width {
        let filled = mask[row * width + x] > 128
        if filled, start == nil { start = x }
        if !filled, let begin = start {
            if x - begin > 2 { spans.append(begin..<x) }
            start = nil
        }
    }
    if let begin = start, width - begin > 2 { spans.append(begin..<width) }
    return spans
}

func write(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Relays/Assets.xcassets/AppIcon.appiconset"

write(drawIcon(size: 1024, background: true, rounded: false, inset: 0, tinted: false), to: "\(out)/icon-ios.png")
write(drawIcon(size: 1024, background: false, rounded: false, inset: 0, tinted: false), to: "\(out)/icon-ios-dark.png")
write(drawIcon(size: 1024, background: false, rounded: false, inset: 0, tinted: true), to: "\(out)/icon-ios-tinted.png")
for (name, value) in [("16", 16), ("16@2x", 32), ("32", 32), ("32@2x", 64),
                      ("128", 128), ("128@2x", 256), ("256", 256), ("256@2x", 512),
                      ("512", 512), ("512@2x", 1024)] {
    let side = CGFloat(value)
    write(drawIcon(size: side, background: true, rounded: true, inset: side * 0.098, tinted: false),
          to: "\(out)/icon-mac-\(name).png")
}
print("wrote icon set to \(out)")
