import AppKit

/// The menu-bar status icon, drawn programmatically as a monochrome *template*
/// image so macOS tints it correctly in both light and dark menu bars.
///
/// The glyph is the Night Walker eclipse: a filled disc with a thin crescent
/// on the right. No third-party assets, no bundled bitmap.
enum MenuBarIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        return EclipseMark.templateImage(size: size)
    }

    /// A tinted (non-template) copy of the glyph, filled with `color`.
    private static func tinted(_ color: NSColor) -> NSImage {
        let base = image()
        let out = NSImage(size: base.size)
        out.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        color.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }

    /// Render an evidence PNG: the icon on a dark bar (white) and a light bar
    /// (black), proving the template reads correctly in both menu-bar looks.
    static func writeEvidence(to path: String) throws {
        let scale: CGFloat = 6
        let iconSize = image().size            // 18 × 18
        let padX: CGFloat = 12, padY: CGFloat = 9, gap: CGFloat = 20
        let barW = iconSize.width + padX * 2, barH = iconSize.height + padY * 2
        let canvas = NSSize(width: (barW * 2 + gap) * scale, height: barH * scale)

        let out = NSImage(size: canvas)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        (NSGraphicsContext.current?.cgContext).map { $0.scaleBy(x: scale, y: scale) }

        func swatch(x: CGFloat, bg: NSColor, tint: NSColor) {
            bg.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: barH), xRadius: 4, yRadius: 4).fill()
            tinted(tint).draw(in: NSRect(x: x + padX, y: padY, width: iconSize.width, height: iconSize.height))
        }
        swatch(x: 0, bg: NSColor(calibratedWhite: 0.13, alpha: 1), tint: .white)
        swatch(x: barW + gap, bg: NSColor(calibratedWhite: 0.93, alpha: 1), tint: NSColor(calibratedWhite: 0.10, alpha: 1))

        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: path))
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        if (attrs[.size] as? NSNumber)?.intValue ?? 0 <= 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
