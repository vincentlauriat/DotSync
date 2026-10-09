#!/usr/bin/env swift
// Draws the DotSync app icon into DotSync/Assets.xcassets/AppIcon.appiconset.
// Concept: a central dot (dotfiles) inside a ring of two sync arrows, with four
// small dots on the ring (the Macs kept in sync). macOS icon grid: 1024 canvas,
// 824 pt rounded-rect body with a soft drop shadow.
// Usage: ./Scripts/make-app-icon.swift [--preview out.png]
import AppKit

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = scriptDir.deletingLastPathComponent()
    .appendingPathComponent("DotSync/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

func draw(_ ctx: CGContext, size: CGFloat) {
    let k = size / 1024                      // everything is designed on a 1024 grid
    let small = size < 64                    // 16/32 px: drop the Mac dots, thicken the ring
    ctx.scaleBy(x: k, y: k)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow, then gradient body (teal top → deep navy bottom)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x1B2A55))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([color(0x2BB5B8), color(0x1F6C9E), color(0x1B2A55)], [0, 0.55, 1]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.drawRadialGradient(gradient([color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)], [0, 1]),
                           startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])
    ctx.restoreGState()

    let c = CGPoint(x: 512, y: 512)
    let r: CGFloat = 255
    let white = color(0xFFFFFF)

    // Two sync arcs (clockwise), each ending in an arrowhead
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x0A1430, 0.35))
    ctx.setStrokeColor(white)
    ctx.setFillColor(white)
    let stroke: CGFloat = small ? 84 : 58
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.butt)
    let gap = CGFloat.pi / 5.2               // angular room left for each arrowhead
    for start in [CGFloat(0), CGFloat.pi] {           // tails at 3 and 9 o'clock
        let from = start
        let end = start - CGFloat.pi + gap   // arc stops short; the arrowhead fills the gap
        ctx.addArc(center: c, radius: r, startAngle: from, endAngle: end, clockwise: true)
        ctx.strokePath()
        // round tail
        let tail = CGPoint(x: c.x + r * cos(from), y: c.y + r * sin(from))
        ctx.fillEllipse(in: CGRect(x: tail.x - stroke / 2, y: tail.y - stroke / 2, width: stroke, height: stroke))
        // arrowhead: base centred on the arc end, tip further along the ring (on the circle,
        // so it reads as following the rotation); leaves a small gap before the next tail
        let base = CGPoint(x: c.x + r * cos(end), y: c.y + r * sin(end))
        let radial = CGPoint(x: cos(end), y: sin(end))
        let tipAngle = end - gap * 0.84
        let half: CGFloat = small ? 80 : 62
        ctx.move(to: CGPoint(x: c.x + r * cos(tipAngle), y: c.y + r * sin(tipAngle)))
        ctx.addLine(to: CGPoint(x: base.x + radial.x * half, y: base.y + radial.y * half))
        ctx.addLine(to: CGPoint(x: base.x - radial.x * half, y: base.y - radial.y * half))
        ctx.closePath()
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Four small dots on the ring: the Macs
    for deg in small ? [] : [60.0, 120.0, 240.0, 300.0] {          // kept clear of the arrowheads (~35° / 215°)
        let a = CGFloat(deg) * .pi / 180
        let d = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        ctx.setFillColor(color(0x1B2A55))
        ctx.fillEllipse(in: CGRect(x: d.x - 46, y: d.y - 46, width: 92, height: 92))
        ctx.setFillColor(color(0x8FF0E6))
        ctx.fillEllipse(in: CGRect(x: d.x - 30, y: d.y - 30, width: 60, height: 60))
    }

    // Central dot with a glow: the dotfiles
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: color(0x8FF0E6, 0.9))
    ctx.setFillColor(white)
    ctx.fillEllipse(in: CGRect(x: c.x - 92, y: c.y - 92, width: 184, height: 184))
    ctx.restoreGState()
}

func render(_ px: Int) -> Data {
    // Exactly px×px pixels (lockFocus would render at the screen's backing scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    draw(ctx, size: CGFloat(px))
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    try! render(1024).write(to: URL(fileURLWithPath: args[i + 1]))
    exit(0)
}

// macOS appiconset: 16…512 at @1x and @2x
let entries: [(size: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                                          (256, 1), (256, 2), (512, 1), (512, 2)]
let fm = FileManager.default
for f in (try? fm.contentsOfDirectory(at: iconset, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "png" {
    try? fm.removeItem(at: f)
}
var images: [[String: String]] = []
for e in entries {
    let name = "icon_\(e.size)x\(e.size)\(e.scale == 2 ? "@2x" : "").png"
    try! render(e.size * e.scale).write(to: iconset.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(e.size)x\(e.size)", "scale": "\(e.scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.appendingPathComponent("Contents.json"))
print("✅ DotSync icon written to \(iconset.path)")
