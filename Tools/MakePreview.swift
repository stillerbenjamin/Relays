//
//  MakePreview.swift
//  Relays — link preview card
//
//  Renders the 1200×630 image that Bluesky, Mastodon and every other client
//  shows when somebody posts a link to the site. Run from the repository root:
//
//      swift Tools/MakePreview.swift
//
//  It writes the same file to two places, because the page is served from both
//  the root and docs/ and `og:image` has to be one absolute URL either way.
//
//  Same palette and same face as the app: the dark ground, Bluesky's blue for
//  what matters, Inter from the app's own resources. The figures are the ones
//  the site leads with — read off relay1.us-west.bsky.network, and the reason
//  the app exists.
//

import AppKit
import CoreGraphics
import CoreText

let regular = URL(fileURLWithPath: "Relays/Resources/Inter-Regular.ttf")
let medium  = URL(fileURLWithPath: "Relays/Resources/Inter-Medium.ttf")
let semibold = URL(fileURLWithPath: "Relays/Resources/Inter-SemiBold.ttf")
for url in [regular, medium, semibold] {
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

/// The site's own tokens, dark set.
let ground   = CGColor(red: 0.031, green: 0.035, blue: 0.043, alpha: 1)   // #08090B
let ink      = CGColor(red: 0.925, green: 0.933, blue: 0.949, alpha: 1)   // #ECEEF2
let muted    = CGColor(red: 0.529, green: 0.557, blue: 0.600, alpha: 1)   // #878E99
let faint    = CGColor(red: 0.337, green: 0.365, blue: 0.404, alpha: 1)   // #565D67
let signal   = CGColor(red: 0.290, green: 0.620, blue: 1.0, alpha: 1)     // #4A9EFF
let hairline = CGColor(red: 0.914, green: 0.933, blue: 0.961, alpha: 0.10)

let width = 1200, height = 630
let margin: CGFloat = 84

func font(_ name: String, _ size: CGFloat) -> NSFont {
    NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
}

func draw(_ text: String, _ nsFont: NSFont, _ colour: CGColor,
          at point: CGPoint, tracking: CGFloat = 0, in ctx: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: nsFont,
        .foregroundColor: NSColor(cgColor: colour)!,
        .kern: tracking
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes))
    ctx.textPosition = point
    CTLineDraw(line, ctx)
}

let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true)

ctx.setFillColor(ground)
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

// The trace field, the same motif the sign-in screen draws: parallel lines, a
// lit stretch on some of them. Seeded, so the picture is the same every run.
var seed: UInt64 = 20260903
func random() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((seed >> 33) % 100_000) / 100_000
}
for index in 0..<26 {
    let band = CGFloat(index) / 25
    let y = (band * CGFloat(height) + (random() - 0.5) * 18).rounded() + 0.5
    let from = random() * CGFloat(width) * 0.7 - CGFloat(width) * 0.15
    let to = min(CGFloat(width), from + (0.25 + random() * 0.7) * CGFloat(width))
    guard to > from else { continue }

    ctx.setStrokeColor(ink.copy(alpha: 0.05 + random() * 0.07)!)
    ctx.setLineWidth(0.6 + random() * 1.1)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: max(0, from), y: y))
    ctx.addLine(to: CGPoint(x: to, y: y))
    ctx.strokePath()

    if random() > 0.6 {
        let litFrom = from + (to - from) * random() * 0.6
        ctx.setStrokeColor(signal.copy(alpha: 0.42)!)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: max(0, litFrom), y: y))
        ctx.addLine(to: CGPoint(x: min(to, litFrom + (to - from) * 0.16), y: y))
        ctx.strokePath()
    }
}

// CoreGraphics has y running up; the layout below reads down from the top.
func fromTop(_ distance: CGFloat) -> CGFloat { CGFloat(height) - distance }

draw("RELAYS", font("Inter-Medium", 26), ink,
     at: CGPoint(x: margin, y: fromTop(margin + 22)), tracking: 6, in: ctx)

draw("A Bluesky client that shows you", font("Inter-Regular", 62), ink,
     at: CGPoint(x: margin, y: fromTop(margin + 132)), tracking: -1.6, in: ctx)
draw("the network underneath.", font("Inter-Regular", 62), signal,
     at: CGPoint(x: margin, y: fromTop(margin + 208)), tracking: -1.6, in: ctx)

draw("Which server hosts a post. Which service moderated it. The firehose itself.",
     font("Inter-Regular", 25), muted,
     at: CGPoint(x: margin, y: fromTop(margin + 278)), in: ctx)

ctx.setStrokeColor(hairline)
ctx.setLineWidth(1)
ctx.beginPath()
ctx.move(to: CGPoint(x: margin, y: fromTop(margin + 344)))
ctx.addLine(to: CGPoint(x: CGFloat(width) - margin, y: fromTop(margin + 344)))
ctx.strokePath()

// The figures the site leads with. The middle one is the argument.
//
// Laid out from measured widths rather than a fixed column pitch: a guessed
// pitch fitted the first three and pushed "iOS + macOS" over the right margin.
// The gap is whatever is left over, shared equally.
let figures: [(String, String, CGColor)] = [
    ("6,156", "SERVERS", ink),
    ("6,067", "NOT BLUESKY'S", signal),
    ("552,880", "ACCOUNTS ON THOSE", ink),
    ("iOS + macOS", "OPEN SOURCE, MIT", ink)
]

let valueFont = font("Inter-SemiBold", 46)
let labelFont = font("Inter-Medium", 16)

func measure(_ text: String, _ nsFont: NSFont, tracking: CGFloat) -> CGFloat {
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: text, attributes: [.font: nsFont, .kern: tracking]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

let columns = figures.map { value, label, _ in
    max(measure(value, valueFont, tracking: -1.2), measure(label, labelFont, tracking: 2.2))
}
let available = CGFloat(width) - margin * 2
let gap = max(24, (available - columns.reduce(0, +)) / CGFloat(figures.count - 1))

var x = margin
for (index, (value, label, colour)) in figures.enumerated() {
    draw(value, valueFont, colour,
         at: CGPoint(x: x, y: fromTop(margin + 412)), tracking: -1.2, in: ctx)
    draw(label, labelFont, faint,
         at: CGPoint(x: x, y: fromTop(margin + 444)), tracking: 2.2, in: ctx)
    x += columns[index] + gap
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let data = rep.representation(using: .png, properties: [:])!
for path in ["preview.png", "docs/preview.png"] {
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)  \(data.count / 1024) KB")
}
