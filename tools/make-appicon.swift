#!/usr/bin/env swift
//
// Renders the app's .iconset PNGs programmatically (no third-party assets, no
// Xcode). bundle.sh runs this, then `iconutil` assembles the .icns.
//
// Same Night Walker eclipse as Sources/.../EclipseMark.swift (keep the unit-
// space numbers in sync): black disc + thin right crescent on a light tile.
// No flames. The menu-bar template is the same silhouette, monochrome.
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
let markCY: CGFloat = 0.50
let markR: CGFloat = 0.40
// Tuned proportions for the disc, gap, and sliver.
let markGapFrac: CGFloat = 0.101
let markOffsetFrac: CGFloat = 0.106
let markMinGap: CGFloat = 1.15
let markMinOffset: CGFloat = 1.45

struct EclipseGeometry {
    var disc: CGRect
    var punch: CGRect
    var outer: CGRect
}

func eclipseGeometry(in rect: CGRect) -> EclipseGeometry {
    let pad = min(rect.width, rect.height) * 0.04
    let box = rect.insetBy(dx: pad, dy: pad)
    let s = min(box.width, box.height)
    let ox = box.midX - s / 2
    let oy = box.midY - s / 2
    let gap = max(markMinGap / s, markGapFrac * markR)
    let offset = max(markMinOffset / s, markOffsetFrac * markR)
    let cx = 0.50 - (gap + offset) / 2
    func oval(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGRect {
        CGRect(x: ox + (cx - r) * s,
               y: oy + (cy - r) * s,
               width: 2 * r * s,
               height: 2 * r * s)
    }
    let punchR = markR + gap
    return EclipseGeometry(
        disc: oval(cx: cx, cy: markCY, r: markR),
        punch: oval(cx: cx, cy: markCY, r: punchR),
        outer: oval(cx: cx + offset, cy: markCY, r: punchR)
    )
}

func draw(_ px: CGFloat) -> NSImage {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size, flipped: false) { rect in
        let corner = px * 0.22
        let tile = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        // Light tile so the black disc reads — same as the canonical jpg.
        let tileColor = NSColor(calibratedWhite: 0.97, alpha: 1)
        tileColor.setFill()
        tile.fill()
        tile.addClip()

        let g = eclipseGeometry(in: rect)

        // Black crescent, then punch the gap with the tile, then black disc.
        NSColor.black.setFill()
        NSBezierPath(ovalIn: g.outer).fill()
        tileColor.setFill()
        NSBezierPath(ovalIn: g.punch).fill()
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
