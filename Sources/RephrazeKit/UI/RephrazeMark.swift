import AppKit
import SwiftUI

/// The app's mark: one continuous stroke that starts as a wide oscillation and
/// settles almost flat.
///
/// That is rephrasing in a single form -- the same line throughout, the same
/// direction, just resolved by the end. Abstract on purpose: it reads at 16pt
/// and does not date, where an illustration turns to mush and looks like every
/// other AI app.
///
/// Defined here rather than in the icon renderer because the mark appears in
/// four places -- the app icon, the menu bar, the result panel and the settings
/// window -- and a mark that differs between them is not a mark. The renderer
/// in scripts/icon/ compiles this same file.
///
/// Two earlier attempts are recorded here as things not to retry: hard mitred
/// corners for the "rough" half produce spikes and read as a heartbeat, which
/// is a different product entirely, and round joins on the same path sand the
/// corners off again. Amplitude carries the meaning here; sharpness does not.
struct RephrazeMark: Shape {

    /// Stroke width as a fraction of the mark's width. Kept with the geometry
    /// because the two are one drawing: scale them apart and the mark at 16pt
    /// stops looking like the mark at 1024.
    static let strokeWidthRatio: CGFloat = 0.098

    /// The mark stroked as the icon strokes it.
    static func strokeStyle(for size: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: size * strokeWidthRatio, lineCap: .round, lineJoin: .round)
    }

    /// Drawn in `rect`'s width, on its horizontal midline. The stroke sits well
    /// inside the rect, so callers can hand over the whole chip or button they
    /// have without insetting it first.
    func path(in rect: CGRect) -> Path {
        let u = rect.width
        let mid = rect.midY
        func x(_ fraction: CGFloat) -> CGFloat { rect.minX + u * fraction }

        var path = Path()
        path.move(to: CGPoint(x: x(0.130), y: mid))

        /// One half-oscillation, flat-to-flat, bulging up by `amplitude`.
        func wave(to endX: CGFloat, amplitude: CGFloat) {
            let startX = path.currentPoint?.x ?? endX
            let span = endX - startX
            path.addCurve(
                to: CGPoint(x: endX, y: mid),
                control1: CGPoint(x: startX + span * 0.36, y: mid - amplitude),
                control2: CGPoint(x: endX - span * 0.36, y: mid - amplitude)
            )
        }

        wave(to: x(0.315), amplitude: u * 0.290)    // wide
        wave(to: x(0.500), amplitude: -u * 0.245)
        wave(to: x(0.675), amplitude: u * 0.145)    // narrowing
        wave(to: x(0.875), amplitude: -u * 0.048)   // settles level, no final kink

        return path
    }
}

/// The mark at a given size, stroked in the current foreground style -- so it
/// drops in where an `Image(systemName:)` used to sit and takes its colour the
/// same way.
struct RephrazeMarkView: View {

    var size: CGFloat

    var body: some View {
        RephrazeMark()
            .stroke(style: RephrazeMark.strokeStyle(for: size))
            .frame(width: size, height: size)
    }
}

extension RephrazeMark {

    /// The mark as a menu bar image.
    ///
    /// Template images take their colour from the menu bar, so this one follows
    /// light and dark, reduced transparency and the highlight while the menu is
    /// open -- none of which a coloured image would do.
    static func templateImage(size: CGFloat) -> NSImage {
        let image = NSImage(
            size: NSSize(width: size, height: size),
            flipped: true    // draw in SwiftUI's coordinates, so the path is the path
        ) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(RephrazeMark().path(in: rect).cgPath)
            ctx.setStrokeColor(NSColor.black.cgColor)    // ignored: the template is a mask
            ctx.setLineWidth(rect.width * strokeWidthRatio)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
