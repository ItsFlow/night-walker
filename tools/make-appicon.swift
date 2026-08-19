#!/usr/bin/env swift
//
// Renders the app's .iconset PNGs programmatically (no third-party assets, no
// Xcode). bundle.sh runs this, then `iconutil` assembles the .icns.
//
// The icon mirrors the app's motif: a day/night split disc (a color filter)
// on a soft rounded gradient tile.
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

func draw(_ px: CGFloat) -> NSImage {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size, flipped: false) { rect in
        // Rounded tile with a vertical warm→cool gradient.
        let corner = px * 0.22
        let tile = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        let bg = NSGradient(colors: [
            NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.28, alpha: 1),
        ])
        bg?.draw(in: tile, angle: -90)

        // Central day/night disc.
        let d = px * 0.56
        let discRect = NSRect(x: (px - d) / 2, y: (px - d) / 2, width: d, height: d)

        // Left half: light (day).
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: rect.minX, y: rect.minY, width: discRect.midX, height: px).clip()
        NSColor(calibratedRed: 0.98, green: 0.86, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(ovalIn: discRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Right half: tinted gradient (night).
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: discRect.midX, y: rect.minY, width: px - discRect.midX, height: px).clip()
        let disc = NSBezierPath(ovalIn: discRect)
        let tint = NSGradient(colors: [
            NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.30, alpha: 1),
            NSColor(calibratedRed: 0.40, green: 0.30, blue: 0.75, alpha: 1),
        ])
        disc.addClip()
        tint?.draw(in: discRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Thin ring for definition.
        let ring = NSBezierPath(ovalIn: discRect)
        ring.lineWidth = max(1, px * 0.012)
        NSColor(calibratedWhite: 1, alpha: 0.35).setStroke()
        ring.stroke()

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
