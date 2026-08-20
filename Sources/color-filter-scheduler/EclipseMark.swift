import AppKit
import SwiftUI

/// Night Walker eclipse: a filled disc with two sharp right-side prominence
/// blades. Same silhouette for the menu-bar template, the panel header, and
/// the dock icon (see `tools/make-appicon.swift`, which reimplements these
/// unit-space numbers so the standalone script stays in sync).
///
/// Unit square, origin bottom-left, y-up. Drawn as one high-contrast shape:
/// blades are filled first, then the disc punches a clean circular rim.
enum EclipseMark {
    struct Geometry {
        var disc: CGRect
        var upper: [CGPoint]
        var lower: [CGPoint]
    }

    /// Disc centre and radius in the unit square. Disc sits left so the two
    /// blades have room to read as separate prominences at ~16px.
    static let cx: CGFloat = 0.34
    static let cy: CGFloat = 0.50
    static let r: CGFloat = 0.28

    static func geometry(in rect: CGRect) -> Geometry {
        let pad = min(rect.width, rect.height) * 0.05
        let box = rect.insetBy(dx: pad, dy: pad)
        let s = min(box.width, box.height)
        // Wider-than-tall (menu bar): pack left so the blades use the extra width.
        let ox = box.width > box.height ? box.minX : box.midX - s / 2
        let oy = box.midY - s / 2

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        let disc = CGRect(x: ox + (cx - r) * s,
                          y: oy + (cy - r) * s,
                          width: 2 * r * s,
                          height: 2 * r * s)

        // Two thin triangles, ~40° of disc between their inner attach points
        // so the valley survives 18px anti-aliasing.
        return Geometry(
            disc: disc,
            upper: triangle(tipDeg: 56, length: 0.36, fromDeg: 70, toDeg: 44)
                .map { pt($0.x, $0.y) },
            lower: triangle(tipDeg: 4, length: 0.38, fromDeg: 16, toDeg: -10)
                .map { pt($0.x, $0.y) }
        )
    }

    /// Sharp 3-point blade in unit space. `fromDeg`/`toDeg` are attach angles
    /// on the disc (CCW from +x); `length` is extra beyond the rim. Bases sit
    /// inside the disc so the disc fill joins them into one silhouette.
    static func triangle(tipDeg: CGFloat, length: CGFloat,
                         fromDeg: CGFloat, toDeg: CGFloat) -> [CGPoint] {
        func rim(_ deg: CGFloat, _ rad: CGFloat) -> CGPoint {
            let a = deg * .pi / 180
            return CGPoint(x: cx + cos(a) * rad, y: cy + sin(a) * rad)
        }
        let base = r * 0.72
        return [rim(fromDeg, base), rim(tipDeg, r + length), rim(toDeg, base)]
    }

    static func fillPoly(_ pts: [CGPoint]) {
        guard let first = pts.first, pts.count >= 3 else { return }
        let p = NSBezierPath()
        p.move(to: first)
        for pt in pts.dropFirst() { p.line(to: pt) }
        p.close()
        p.fill()
    }

    /// Monochrome fill (menu-bar template / panel glyph).
    static func fill(in rect: CGRect, color: NSColor) {
        let g = geometry(in: rect)
        color.setFill()
        fillPoly(g.upper)
        fillPoly(g.lower)
        NSBezierPath(ovalIn: g.disc).fill()
    }
}

/// Panel-header glyph: the same eclipse, filled with the current primary color.
struct EclipseGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let g = EclipseMark.geometry(in: rect)
            ZStack {
                poly(g.upper).fill(Color.primary)
                poly(g.lower).fill(Color.primary)
                Ellipse().path(in: g.disc).fill(Color.primary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func poly(_ pts: [CGPoint]) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
        }
    }
}
