// Regenerates BlindensportGraz/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
//   swift generate_app_icon.swift BlindensportGraz/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// White "blind pedestrian" pictogram (person walking with a white cane) on a
// solid blue background. The glyph is Google's Material Symbols "blind" icon
// (Apache License 2.0, https://github.com/google/material-design-icons) — its
// single SVG path is parsed into a CGPath here and filled white, centred with
// margin. Output is opaque 24-bit RGB (no alpha) — the App Store rejects an
// app icon PNG that carries an alpha channel.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("ctx")
}

// Top-left origin coordinate space (y down), matching the SVG viewBox below.
ctx.translateBy(x: 0, y: CGFloat(S))
ctx.scaleBy(x: 1, y: -1)

// ---- Background: solid blue ----
ctx.setFillColor(CGColor(red: 0.145, green: 0.427, blue: 0.914, alpha: 1)) // #256DE9
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// ---- Foreground: Material Symbols "blind" glyph, filled white ----
// Rounded filled variant. viewBox "0 -960 960 960": y grows downward, the top
// edge is y = -960 and the bottom edge y = 0.
let svgPath = "M460-760q-33 0-56.5-23.5T380-840q0-33 23.5-56.5T460-920q33 0 56.5 23.5T540-840q0 33-23.5 56.5T460-760Zm260 260q0 17-11.5 28.5T680-460h-39L850-95q5 8 2.5 15T842-68q-8 5-15 3t-12-10L588-471q-40-13-72.5-37.5T460-568q-10 29-15.5 66.5T441-432l79 112v220q0 17-11.5 28.5T480-60q-17 0-28.5-11.5T440-100v-160l-71-102-9 142-96 128q-10 14-26 16t-30-8q-14-10-16-26t8-30l80-107v-213q0-31 5.5-68.5T300-596l-60 34v102q0 17-11.5 28.5T200-420q-17 0-28.5-11.5T160-460v-125q0-11 5.5-20.5T180-620l196-111q8-5 17-7t19-2q24 0 44 12t30 33l31 67q20 44 61 66t102 22q17 0 28.5 11.5T720-500Z"

// Fit the 960x960 viewBox into a centred square with margin.
let glyph = CGFloat(S) * 0.66
let off = (CGFloat(S) - glyph) / 2
let path = SVGPath.cgPath(from: svgPath) { vx, vy in
    let nx = (vx - 0) / 960
    let ny = (vy - (-960)) / 960
    return CGPoint(x: off + CGFloat(nx) * glyph, y: off + CGFloat(ny) * glyph)
}
ctx.addPath(path)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath(using: .winding)

guard let img = ctx.makeImage() else { fatalError("img") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
guard let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                                UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dst")
}
CGImageDestinationAddImage(dst, img, nil)
guard CGImageDestinationFinalize(dst) else { fatalError("finalize") }
print("wrote \(out)")

// MARK: - Minimal SVG path parser: M m L l H h V v C c S s Q q T t Z z

enum SVGPath {
    private enum Token { case cmd(Character); case num(Double) }

    private static func tokenize(_ d: String) -> [Token] {
        var out: [Token] = []
        let s = Array(d.unicodeScalars)
        var i = 0
        while i < s.count {
            let c = Character(s[i])
            if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { i += 1; continue }
            if c.isLetter { out.append(.cmd(c)); i += 1; continue }
            // number
            var str = ""
            if c == "-" || c == "+" { str.append(c); i += 1 }
            var seenDot = false, seenExp = false
            while i < s.count {
                let ch = Character(s[i])
                if ch.isNumber { str.append(ch); i += 1 }
                else if ch == "." && !seenDot && !seenExp { seenDot = true; str.append(ch); i += 1 }
                else if (ch == "e" || ch == "E") && !seenExp {
                    seenExp = true; str.append(ch); i += 1
                    if i < s.count, s[i] == "-" || s[i] == "+" { str.append(Character(s[i])); i += 1 }
                } else { break }
            }
            if let v = Double(str) { out.append(.num(v)) }
        }
        return out
    }

    static func cgPath(from d: String, map t: (Double, Double) -> CGPoint) -> CGPath {
        let toks = tokenize(d)
        let p = CGMutablePath()
        var k = 0
        var cur = (x: 0.0, y: 0.0)
        var startPt = (x: 0.0, y: 0.0)
        var prevQuadCtrl: (x: Double, y: Double)?
        var prevCubicCtrl: (x: Double, y: Double)?

        func num() -> Double {
            while k < toks.count { if case .num(let v) = toks[k] { k += 1; return v }; k += 1 }
            return 0
        }
        func nextIsNum() -> Bool { k < toks.count && { if case .num = toks[k] { return true } else { return false } }() }

        var idx = 0
        var lastCmd: Character = " "
        while idx < toks.count {
            guard case .cmd(let raw) = toks[idx] else { idx += 1; continue }
            idx += 1
            // advance the number cursor `k` to just past this command letter
            k = idx
            let rel = raw.isLowercase
            let cmd = Character(raw.uppercased())

            repeat {
                switch cmd {
                case "M":
                    let x = (rel ? cur.x : 0) + num(), y = (rel ? cur.y : 0) + num()
                    cur = (x, y); startPt = cur
                    p.move(to: t(x, y))
                    prevQuadCtrl = nil; prevCubicCtrl = nil
                    // subsequent pairs are implicit L/l
                    while nextIsNum() {
                        let lx = (rel ? cur.x : 0) + num(), ly = (rel ? cur.y : 0) + num()
                        cur = (lx, ly); p.addLine(to: t(lx, ly))
                    }
                case "L":
                    let x = (rel ? cur.x : 0) + num(), y = (rel ? cur.y : 0) + num()
                    cur = (x, y); p.addLine(to: t(x, y))
                    prevQuadCtrl = nil; prevCubicCtrl = nil
                case "H":
                    let x = (rel ? cur.x : 0) + num()
                    cur = (x, cur.y); p.addLine(to: t(cur.x, cur.y))
                    prevQuadCtrl = nil; prevCubicCtrl = nil
                case "V":
                    let y = (rel ? cur.y : 0) + num()
                    cur = (cur.x, y); p.addLine(to: t(cur.x, cur.y))
                    prevQuadCtrl = nil; prevCubicCtrl = nil
                case "C":
                    let c1x = (rel ? cur.x : 0) + num(), c1y = (rel ? cur.y : 0) + num()
                    let c2x = (rel ? cur.x : 0) + num(), c2y = (rel ? cur.y : 0) + num()
                    let x = (rel ? cur.x : 0) + num(), y = (rel ? cur.y : 0) + num()
                    p.addCurve(to: t(x, y), control1: t(c1x, c1y), control2: t(c2x, c2y))
                    prevCubicCtrl = (c2x, c2y); prevQuadCtrl = nil
                    cur = (x, y)
                case "S":
                    let rx = prevCubicCtrl.map { 2*cur.x - $0.x } ?? cur.x
                    let ry = prevCubicCtrl.map { 2*cur.y - $0.y } ?? cur.y
                    let c2x = (rel ? cur.x : 0) + num(), c2y = (rel ? cur.y : 0) + num()
                    let x = (rel ? cur.x : 0) + num(), y = (rel ? cur.y : 0) + num()
                    p.addCurve(to: t(x, y), control1: t(rx, ry), control2: t(c2x, c2y))
                    prevCubicCtrl = (c2x, c2y); prevQuadCtrl = nil
                    cur = (x, y)
                case "Q":
                    let cx = (rel ? cur.x : 0) + num(), cy = (rel ? cur.y : 0) + num()
                    let x = (rel ? cur.x : 0) + num(), y = (rel ? cur.y : 0) + num()
                    p.addQuadCurve(to: t(x, y), control: t(cx, cy))
                    prevQuadCtrl = (cx, cy); prevCubicCtrl = nil
                    cur = (x, y)
                case "T":
                    let cx = prevQuadCtrl.map { 2*cur.x - $0.x } ?? cur.x
                    let cy = prevQuadCtrl.map { 2*cur.y - $0.y } ?? cur.y
                    let x = (rel ? cur.x : 0) + num(), y = (rel ? cur.y : 0) + num()
                    p.addQuadCurve(to: t(x, y), control: t(cx, cy))
                    prevQuadCtrl = (cx, cy); prevCubicCtrl = nil
                    cur = (x, y)
                case "Z":
                    p.closeSubpath()
                    cur = startPt
                    prevQuadCtrl = nil; prevCubicCtrl = nil
                default:
                    break
                }
                lastCmd = cmd
                _ = lastCmd
            } while cmd != "Z" && cmd != "M" && nextIsNum()

            idx = k
        }
        return p
    }
}
