import AppKit
import SwiftUI

/// Night Walker eclipse: a filled disc with a thin crescent on the right
/// (no flames, spikes, or rays). Same silhouette for the menu-bar template,
/// the panel header, and the dock icon — keep `tools/make-appicon.swift` in
/// sync with these unit-space numbers.
///
/// Unit square, origin bottom-left, y-up. Crescent = a same-radius circle
/// offset right, minus the disc expanded by `gap` (the white slit).
enum EclipseMark {
    struct Geometry {
        var disc: CGRect
        var punch: CGRect
        var outer: CGRect
    }

    static let cx: CGFloat = 0.48
    static let cy: CGFloat = 0.50
    static let r: CGFloat = 0.36
    static let gap: CGFloat = 0.055
    static let offset: CGFloat = 0.065

    static func geometry(in rect: CGRect) -> Geometry {
        let pad = min(rect.width, rect.height) * 0.06
        let box = rect.insetBy(dx: pad, dy: pad)
        let s = min(box.width, box.height)
        let ox = box.midX - s / 2
        let oy = box.midY - s / 2

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
}

/// Panel-header glyph: the same eclipse, template-tinted.
struct EclipseGlyph: View {
    var body: some View {
        Image(nsImage: MenuBarIcon.image())
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
    }
}
