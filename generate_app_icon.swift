// Regenerates BlindensportGraz/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
//   swift generate_app_icon.swift BlindensportGraz/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// Draws the international "person walking with a white cane" symbol in white on
// the app's blue->purple diagonal gradient. Output is opaque 24-bit RGB (no
// alpha) — the App Store rejects an app icon PNG that carries an alpha channel.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
// noneSkipLast => opaque, no alpha channel semantics (App Store rejects an
// app icon PNG that carries alpha, even when nothing is transparent).
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("ctx")
}

// Top-left origin coordinate space (y down).
ctx.translateBy(x: 0, y: CGFloat(S))
ctx.scaleBy(x: 1, y: -1)

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// ---- Background: diagonal blue -> purple gradient (matches the old icon) ----
let c1 = CGColor(red: 0.322, green: 0.549, blue: 0.949, alpha: 1) // ~#528CF2
let c2 = CGColor(red: 0.612, green: 0.435, blue: 0.867, alpha: 1) // ~#9C6FDD
let grad = CGGradient(colorsSpace: cs, colors: [c1, c2] as CFArray, locations: [0, 1])!
ctx.saveGState()
ctx.addRect(CGRect(x: 0, y: 0, width: S, height: S))
ctx.clip()
ctx.drawLinearGradient(grad, start: P(0, 0), end: P(CGFloat(S), CGFloat(S)), options: [])
ctx.restoreGState()

// ---- Foreground: white "person walking with a white cane" pictogram ----
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
ctx.setStrokeColor(white)
ctx.setFillColor(white)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

func stroke(_ pts: [CGPoint], _ w: CGFloat) {
    ctx.setLineWidth(w)
    ctx.beginPath()
    ctx.addLines(between: pts)
    ctx.strokePath()
}
func dot(_ c: CGPoint, _ r: CGFloat) {
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2*r, height: 2*r))
}

// Head
dot(P(454, 194), 70)
// Torso (slight forward lean, walking)
stroke([P(468, 268), P(446, 536)], 100)
// Back leg (trailing, pushing off)
stroke([P(452, 536), P(356, 800)], 58)
// Front leg (mid-stride, bent at the knee)
stroke([P(452, 536), P(524, 648), P(560, 808)], 58)
// Back arm (bent, hand clearing the hip on the lower left)
stroke([P(452, 312), P(430, 402), P(372, 476)], 42)
// Front arm (reaching forward and down to the cane grip)
stroke([P(476, 314), P(602, 420)], 44)
// White cane: continues from the leading hand diagonally to the tip on the ground
stroke([P(602, 420), P(808, 840)], 24)
// Cane tip
dot(P(808, 840), 21)

guard let img = ctx.makeImage() else { fatalError("img") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : "/private/tmp/claude-501/-Users-franz-dev-BlindensportGraz/fb41bc4a-fcd5-49ae-960d-e0a64acb5c99/scratchpad/icon-new.png"
guard let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                                UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dst")
}
CGImageDestinationAddImage(dst, img, nil)
guard CGImageDestinationFinalize(dst) else { fatalError("finalize") }
print("wrote \(out)")
