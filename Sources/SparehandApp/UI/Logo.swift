import AppKit
import SwiftUI

/// Sparehand's mark: an open hand with a second, lighter hand behind it ("a spare pair of hands").
/// Drawn from shapes (no SF Symbols in the logo), in a unit square.
struct HandShape: Shape {
    func path(in r: CGRect) -> Path {
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: r.minX + x * r.width, y: r.minY + y * r.height, width: w * r.width, height: h * r.height)
        }
        var p = Path()
        // Palm.
        p.addRoundedRect(in: rect(0.27, 0.43, 0.46, 0.43), cornerSize: CGSize(width: 0.14 * r.width, height: 0.14 * r.width))
        // Four fingers, staggered like a relaxed open hand.
        let fingers: [(x: CGFloat, top: CGFloat)] = [(0.275, 0.17), (0.39, 0.10), (0.505, 0.13), (0.62, 0.22)]
        for f in fingers {
            p.addRoundedRect(in: rect(f.x, f.top, 0.105, 0.62 - f.top), cornerSize: CGSize(width: 0.0525 * r.width, height: 0.0525 * r.width))
        }
        // Thumb, angled out from the palm.
        let thumb = Path(roundedRect: rect(0.0, 0.0, 0.105, 0.30), cornerSize: CGSize(width: 0.0525 * r.width, height: 0.0525 * r.width))
        let t = CGAffineTransform(translationX: r.minX + 0.10 * r.width, y: r.minY + 0.46 * r.height).rotated(by: -.pi / 4.2)
        p.addPath(thumb, transform: t)
        return p
    }
}

/// The two hands, front and spare.
struct HandsMark: View {
    var color: Color = .white
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                HandShape().fill(color.opacity(0.38))
                    .frame(width: s * 0.86, height: s * 0.86)
                    .rotationEffect(.degrees(-14))
                    .offset(x: -s * 0.13, y: s * 0.02)
                HandShape().fill(color)
                    .frame(width: s * 0.86, height: s * 0.86)
                    .rotationEffect(.degrees(6))
                    .offset(x: s * 0.07, y: s * 0.01)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// The app icon: the hands on a warm tile.
struct SparehandLogo: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF0752E), Color(hex: 0xC2410C)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: size * 0.008)
            HandsMark().frame(width: size * 0.74, height: size * 0.74).offset(x: size * 0.015, y: size * 0.03)
        }
        .frame(width: size, height: size)
    }
}

enum LogoExport {
    /// Renders the icon to PNG (used by scripts/make-icon.sh and the video).
    @MainActor static func png(size: CGFloat, to url: URL, padded: Bool = true) throws {
        // macOS icons sit inside a margin of about 10% of the canvas.
        let view = SparehandLogo(size: padded ? size * 0.8 : size).frame(width: size, height: size)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let cg = r.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    /// A monochrome template for the menu bar.
    @MainActor static func menuBarImage() -> NSImage {
        let view = HandsMark(color: .black).frame(width: 18, height: 18)
        let r = ImageRenderer(content: view)
        r.scale = 2
        let img = r.nsImage ?? NSImage()
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }
}
