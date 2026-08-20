import AppKit
import SwiftUI

/// Night Walker eclipse: a filled disc with a thin crescent on the right
/// (no flames, spikes, or rays). Canonical silhouette is
/// `menu-bar-mark.jpg` — a large disc and a hairline solar sliver.
/// Keep `tools/make-appicon.swift` in sync with these numbers.
///
/// Unit square, origin bottom-left, y-up. Crescent = a same-radius circle
/// offset right, minus the disc expanded by `gap` (the white slit).
/// Gap and offset are fractions of `r` at large sizes, and at least ~1pt
/// at menu-bar size so the sliver still reads.
enum EclipseMark {
    struct Geometry {
        var disc: CGRect
        var punch: CGRect
        var outer: CGRect
    }

    static let cy: CGFloat = 0.50
    static let r: CGFloat = 0.40
    // Measured from the canonical 1024px jpg (disc r=208, gap=21, sliver=22).
    static let gapFrac: CGFloat = 0.101
    static let offsetFrac: CGFloat = 0.106
    static let minGap: CGFloat = 1.15       // points, small sizes
    static let minOffset: CGFloat = 1.45

    static func geometry(in rect: CGRect) -> Geometry {
        let pad = min(rect.width, rect.height) * 0.04
        let box = rect.insetBy(dx: pad, dy: pad)
        let s = min(box.width, box.height)
        let ox = box.midX - s / 2
        let oy = box.midY - s / 2

        let gap = max(minGap / s, gapFrac * r)
        let offset = max(minOffset / s, offsetFrac * r)
        // Centre the disc+sliver as a whole, not the disc alone.
        let cx = 0.50 - (gap + offset) / 2

        func oval(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGRect {
            CGRect(x: ox + (cx - r) * s,
                   y: oy + (cy - r) * s,
                   width: 2 * r * s,
                   height: 2 * r * s)
        }

        let punchR = r + gap
        return Geometry(
            disc: oval(cx: cx, cy: cy, r: r),
            punch: oval(cx: cx, cy: cy, r: punchR),
            outer: oval(cx: cx + offset, cy: cy, r: punchR)
        )
    }

    /// Monochrome fill (menu-bar template / panel glyph).
    static func fill(in rect: CGRect, color: NSColor) {
        let g = geometry(in: rect)
        color.setFill()
        NSBezierPath(ovalIn: g.outer).fill()
        if let ctx = NSGraphicsContext.current {
            ctx.saveGraphicsState()
            ctx.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: g.punch).fill()
            ctx.restoreGraphicsState()
        }
        color.setFill()
        NSBezierPath(ovalIn: g.disc).fill()
    }

    static func templateImage(size: NSSize) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            fill(in: rect, color: .black)
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// Panel-header glyph: the same eclipse, drawn at the view's size so the
/// sliver is not a scaled 18px bitmap.
struct EclipseGlyph: View {
    var body: some View {
        GeometryReader { geo in
            Image(nsImage: EclipseMark.templateImage(size: NSSize(width: geo.size.width,
                                                                  height: geo.size.height)))
                .resizable()
                .renderingMode(.template)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
