#!/usr/bin/env swift
//
// Renders the app's .iconset PNGs programmatically (no third-party assets, no
// Xcode). bundle.sh runs this, then `iconutil` assembles the .icns.
//
// Same Night Walker eclipse as Sources/.../EclipseMark.swift (keep the unit-
// space numbers in sync): filled disc + two right-side prominence blades.
// Dock/app icon tints the blades red on a dark tile; the silhouette is unchanged.
//
// Usage: swift tools/make-appicon.swift <output-iconset-dir>

import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-appicon.swift <iconset-dir>\n".utf8))
    exit(2)
}
let outDir = args[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Unit square, origin bottom-left, y-up. Must match EclipseMark.swift.
let markCX: CGFloat = 0.34
let markCY: CGFloat = 0.50
let markR: CGFloat = 0.28

struct EclipseGeometry {
    var disc: CGRect
    var upper: [CGPoint]
    var lower: [CGPoint]
}

func triangle(tipDeg: CGFloat, length: CGFloat,
              fromDeg: CGFloat, toDeg: CGFloat) -> [CGPoint] {
    func rim(_ deg: CGFloat, _ rad: CGFloat) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: markCX + cos(a) * rad, y: markCY + sin(a) * rad)
    }
    let base = markR * 0.72
    return [rim(fromDeg, base), rim(tipDeg, markR + length), rim(toDeg, base)]
}

func eclipseGeometry(in rect: CGRect) -> EclipseGeometry {
    let pad = min(rect.width, rect.height) * 0.05
    let box = rect.insetBy(dx: pad, dy: pad)
    let s = min(box.width, box.height)
    let ox = box.width > box.height ? box.minX : box.midX - s / 2
    let oy = box.midY - s / 2
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: ox + x * s, y: oy + y * s)
    }
    let disc = CGRect(x: ox + (markCX - markR) * s,
                      y: oy + (markCY - markR) * s,
                      width: 2 * markR * s,
                      height: 2 * markR * s)
    return EclipseGeometry(
        disc: disc,
        upper: triangle(tipDeg: 56, length: 0.36, fromDeg: 70, toDeg: 44)
            .map { pt($0.x, $0.y) },
        lower: triangle(tipDeg: 4, length: 0.38, fromDeg: 16, toDeg: -10)
            .map { pt($0.x, $0.y) }
    )
}

func fillPoly(_ pts: [CGPoint]) {
    guard let first = pts.first, pts.count >= 3 else { return }
    let p = NSBezierPath()
    p.move(to: first)
    for pt in pts.dropFirst() { p.line(to: pt) }
    p.close()
    p.fill()
}

func draw(_ px: CGFloat) -> NSImage {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size, flipped: false) { rect in
        let corner = px * 0.22
        let tile = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
        tile.fill()
        tile.addClip()

        let g = eclipseGeometry(in: rect)

        // Flares: a touch of red. Same blades as the monochrome template.
        NSColor(calibratedRed: 0.92, green: 0.22, blue: 0.07, alpha: 1).setFill()
        fillPoly(g.upper)
        fillPoly(g.lower)

        // Disc on top — black void, clean circular rim.
        NSColor.black.setFill()
        NSBezierPath(ovalIn: g.disc).fill()

        return true
    }
    return img
}

func writePNG(_ image: NSImage, px: Int, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

// (point size, scale) pairs iconutil expects.
let specs: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (pt, scale) in specs {
    let px = pt * scale
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    writePNG(draw(CGFloat(px)), px: px, to: "\(outDir)/\(name)")
}
print("wrote iconset -> \(outDir)")
