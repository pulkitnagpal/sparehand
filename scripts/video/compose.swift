// Composes the Sparehand 1.0 film from real captures (scripts/video/make-film.sh runs it).
// Every window, card, page and note in the film is a capture of the real product from a real run; this file only
// adds the stage: camera moves, focus, transitions and type. Writes raw BGRA frames to stdout for ffmpeg.
//
//   compose <assets dir> <demo home> > frames.raw
import AppKit
import CoreGraphics
import CoreText
import Foundation
import UniformTypeIdentifiers

let W: CGFloat = 1920, H: CGFloat = 1080, FPS = 30.0
let A = URL(fileURLWithPath: CommandLine.arguments[1])
let HOME_DEMO = URL(fileURLWithPath: CommandLine.arguments[2])

// MARK: - palette and type

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let INK = rgb(0x16161A), BODY = rgb(0x3F3F46), MUTED = rgb(0x6B6B74), PAPER = rgb(0xF7F6F3), ORANGE = rgb(0xC2410C)
let ORANGE2 = rgb(0xF0752E), TEAL = rgb(0x0F766E), NIGHT = rgb(0x111114)

func font(_ size: CGFloat, _ weight: NSFont.Weight, rounded: Bool = false) -> CTFont {
    var f = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = f.fontDescriptor.withDesign(.rounded) { f = NSFont(descriptor: d, size: size) ?? f }
    return f as CTFont
}

// MARK: - images

func load(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
func scaled(_ img: CGImage, width: Int) -> CGImage {
    let h = Int(CGFloat(img.height) * CGFloat(width) / CGFloat(img.width))
    let c = CGContext(data: nil, width: width, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(img, in: CGRect(x: 0, y: 0, width: width, height: h))
    return c.makeImage()!
}
func icon(_ ns: NSImage, _ px: Int = 256) -> CGImage {
    var r = CGRect(x: 0, y: 0, width: px, height: px)
    return ns.cgImage(forProposedRect: &r, context: nil, hints: nil)!
}
func film(_ name: String) -> CGImage? { load(A.appendingPathComponent("film/\(name).png")) }
func frames(_ prefix: String) -> [CGImage] {
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: A.appendingPathComponent("film").path)) ?? [])
        .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".png") }.sorted()
    return names.compactMap { film(String($0.dropLast(4))) }
}

let logo = load(A.appendingPathComponent("logo/logo_full.png"))!
let shots = (((try? FileManager.default.contentsOfDirectory(atPath: A.appendingPathComponent("desktop-shots").path)) ?? []).sorted())
    .compactMap { load(A.appendingPathComponent("desktop-shots/\($0)")) }
    .map { scaled($0.cropping(to: CGRect(x: 0, y: 0, width: CGFloat($0.width) * 0.62, height: CGFloat($0.height) * 0.5)) ?? $0, width: 260) }
/// Removes a band of rows (a browser's one-off info bar) and closes the gap, keeping the image size.
func removeRows(_ img: CGImage, from: Int, to: Int) -> CGImage {
    let w = img.width, h = img.height
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let top = img.cropping(to: CGRect(x: 0, y: 0, width: w, height: from))!
    let rest = img.cropping(to: CGRect(x: 0, y: to, width: w, height: h - to))!
    c.draw(top, in: CGRect(x: 0, y: h - from, width: w, height: from))
    c.draw(rest, in: CGRect(x: 0, y: h - from - (h - to), width: w, height: h - to))
    return c.makeImage()!
}
let tabs: [CGImage] = (1...5).compactMap { load(A.appendingPathComponent("browser/tab\($0).png")) }.enumerated()
    .map { i, img in i == 0 && img.width == 2560 ? removeRows(img, from: 164, to: 274) : img }   // Brave's first-run analytics bar
let folderIcon = icon(NSWorkspace.shared.icon(for: .folder))
let trashEmpty = icon(NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns") ?? NSImage())
let trashFull = icon(NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FullTrashIcon.icns") ?? NSImage())
let dmgIcon = icon(NSWorkspace.shared.icon(for: UTType(filenameExtension: "dmg") ?? .data))
let pkgIcon = icon(NSWorkspace.shared.icon(for: UTType(filenameExtension: "pkg") ?? .data))

let cards = film("cards"), dashForYou = film("dash-for-you"), sortDetail = film("sort-detail"), binDetail = film("bin-detail")
let noteDetail = film("note-detail"), today = film("dash-today"), repeatCards = film("repeat-cards")
let sortCards = frames("sort-card-"), binCards = frames("bin-card-"), notes = frames("note-notes-"), sortDone = film("sort-done-card"), binDone = film("bin-done-card")
let noteDone = film("note-done-dash")
func cropX(_ img: CGImage?, from: CGFloat) -> CGImage? {
    guard let img else { return nil }
    return img.cropping(to: CGRect(x: CGFloat(img.width) * from, y: 0, width: CGFloat(img.width) * (1 - from), height: CGFloat(img.height)))
}
/// Notes shows only the note being written, never the list of other notes.
let noteFrames = notes.compactMap { cropX($0, from: 0.445) }
/// Finder shows only the files, never the sidebar.
func finder(_ name: String) -> CGImage? { cropX(load(A.appendingPathComponent("finder/\(name).png")), from: 0.158) }
let desktopBefore = finder("desktop-before"), sortedAfter = finder("sorted-after")
let downloadsBefore = finder("downloads-before"), downloadsAfter = finder("downloads-after")

// Real results from the run.
// The Downloads folder as it was before Sparehand cleared it (written when the scene is set up).
let installers = ((try? String(contentsOf: A.appendingPathComponent("downloads.txt"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
let pictures = HOME_DEMO.appendingPathComponent("Pictures")
let sortRoot = ((try? FileManager.default.contentsOfDirectory(at: pictures, includingPropertiesForKeys: nil)) ?? []).first
let folders: [(String, Int)] = ((try? FileManager.default.contentsOfDirectory(atPath: sortRoot?.path ?? "")) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    .map { ($0, ((try? FileManager.default.contentsOfDirectory(atPath: sortRoot!.appendingPathComponent($0).path)) ?? []).filter { $0.hasSuffix(".png") }.count) }
let filmLog = (try? JSONSerialization.jsonObject(with: Data(contentsOf: A.appendingPathComponent("film/film.json")))) as? [[String: Any]] ?? []
func logged(_ event: String, _ key: String) -> String { (filmLog.first { $0["event"] as? String == event }?[key] as? String) ?? "" }
let sortNote = logged("sort done", "note"), binNote = logged("bin done", "note")
let freed = binNote.components(separatedBy: " · ").first?.replacingOccurrences(of: "Freed ", with: "") ?? "2.5 GB"
let sortedCount = sortNote.split(separator: " ").dropFirst().first.map(String.init) ?? "72"

// MARK: - easing

func clamp(_ x: CGFloat, _ a: CGFloat = 0, _ b: CGFloat = 1) -> CGFloat { min(max(x, a), b) }
func seg(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { clamp((t - a) / (b - a)) }
func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
func easeInOut(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func back(_ t: CGFloat) -> CGFloat { let c1: CGFloat = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2) }
func spring(_ t: CGFloat) -> CGFloat { t >= 1 ? 1 : 1 - exp(-6.5 * t) * cos(11 * t) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func lerpPt(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t)) }

// MARK: - drawing (top-left coordinates)

var ctx: CGContext!
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: H - y - h, width: w, height: h) }

func fill(_ c: CGColor) { ctx.setFillColor(c); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }

func glow(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: center.x, y: H - center.y), startRadius: 0,
                           endCenter: CGPoint(x: center.x, y: H - center.y), endRadius: radius, options: [])
}

/// An image placed by its top-left corner, with rounded corners and a soft shadow.
func image(_ img: CGImage?, _ x: CGFloat, _ y: CGFloat, width w: CGFloat, alpha: CGFloat = 1, radius: CGFloat = 0,
           shadow: CGFloat = 1, rotate: CGFloat = 0, scale: CGFloat = 1) {
    guard let img, alpha > 0.001 else { return }
    let h = w * CGFloat(img.height) / CGFloat(img.width)
    ctx.saveGState()
    ctx.setAlpha(alpha)
    let cx = x + w / 2, cy = y + h / 2
    ctx.translateBy(x: cx, y: H - cy); ctx.rotate(by: rotate); ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -cx, y: -(H - cy))
    let r = R(x, y, w, h)
    let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if shadow > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14 * shadow), blur: 44 * shadow, color: rgb(0x000000, 0.20))
        ctx.addPath(path); ctx.setFillColor(rgb(0xFFFFFF, radius > 0 ? 1 : 0.01)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(img, in: r)
    ctx.restoreGState()
}
func imageHeight(_ img: CGImage?, width: CGFloat) -> CGFloat { guard let img else { return 0 }; return width * CGFloat(img.height) / CGFloat(img.width) }

@discardableResult
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .bold, color: CGColor = INK,
          alpha: CGFloat = 1, rounded: Bool = false, center: Bool = false, kern: CGFloat = 0) -> CGFloat {
    guard alpha > 0.001 else { return 0 }
    let f = font(size, weight, rounded: rounded)
    let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color.copy(alpha: color.alpha * alpha)!, .kern: kern]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.textPosition = CGPoint(x: center ? x - width / 2 : x, y: H - y - CTFontGetAscent(f))
    CTLineDraw(line, ctx)
    return width
}

/// A caption: a big line rising into place with a smaller line under it.
func caption(_ title: String, _ sub: String?, t: CGFloat, start: CGFloat, end: CGFloat, x: CGFloat = 120, y: CGFloat = 120, dark: Bool = false, plate: Bool = false) {
    let inT = easeOut(seg(t, start, start + 0.6)), out = 1 - easeOut(seg(t, end - 0.4, end))
    let a = inT * out
    if plate && a > 0 {
        ctx.saveGState(); ctx.setAlpha(a * 0.94)
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: rgb(0, 0.12))
        ctx.addPath(CGPath(roundedRect: R(x - 32, y - 26, 1180, sub == nil ? 118 : 170), cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath(); ctx.restoreGState()
    }
    text(title, x, y + (1 - inT) * 26, size: 58, weight: .bold, color: dark ? rgb(0xFFFFFF) : INK, alpha: a, kern: -1)
    if let sub {
        let s = easeOut(seg(t, start + 0.25, start + 0.85)) * out
        text(sub, x, y + 82 + (1 - s) * 20, size: 30, weight: .medium, color: dark ? rgb(0xFFFFFF, 0.7) : BODY, alpha: s)
    }
}

func pill(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, fg: CGColor, bg: CGColor, alpha: CGFloat = 1, center: Bool = false) {
    guard alpha > 0.001 else { return }
    let f = font(size, .semibold)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: f]))
    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + size * 1.4, h = size * 2
    let x0 = center ? x - w / 2 : x
    ctx.saveGState(); ctx.setAlpha(alpha)
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: rgb(0, 0.12))
    ctx.addPath(CGPath(roundedRect: R(x0, y, w, h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
    ctx.setFillColor(bg); ctx.fillPath()
    ctx.restoreGState()
    text(s, x0 + size * 0.7, y + size * 0.42, size: size, weight: .semibold, color: fg, alpha: alpha)
}

/// Dims everything except a rounded rectangle.
func spotlight(_ hole: CGRect, alpha: CGFloat, radius: CGFloat = 18) {
    guard alpha > 0.001 else { return }
    let p = CGMutablePath()
    p.addRect(CGRect(x: 0, y: 0, width: W, height: H))
    p.addPath(CGPath(roundedRect: R(hole.minX, hole.minY, hole.width, hole.height), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.saveGState(); ctx.addPath(p); ctx.setFillColor(rgb(0x3A2A20, 0.16 * alpha)); ctx.fillPath(using: .evenOdd); ctx.restoreGState()
    ctx.saveGState(); ctx.setStrokeColor(rgb(0xF0752E, 0.75 * alpha)); ctx.setLineWidth(3)
    ctx.addPath(CGPath(roundedRect: R(hole.minX - 3, hole.minY - 3, hole.width + 6, hole.height + 6), cornerWidth: radius + 3, cornerHeight: radius + 3, transform: nil))
    ctx.strokePath(); ctx.restoreGState()
}

/// Zooms the stage around a focus point (top-left coords) for everything drawn inside.
func camera(scale: CGFloat, focus: CGPoint, _ draw: () -> Void) {
    ctx.saveGState()
    let fx = focus.x, fy = H - focus.y
    ctx.translateBy(x: W / 2, y: H / 2); ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -fx, y: -fy)
    draw()
    ctx.restoreGState()
}

func ripple(_ p: CGPoint, _ k: CGFloat) {
    guard k > 0, k < 1 else { return }
    let r = lerp(8, 44, easeOut(k))
    ctx.saveGState(); ctx.setStrokeColor(rgb(0xF0752E, 0.55 * (1 - k))); ctx.setLineWidth(3)
    ctx.strokeEllipse(in: R(p.x - r, p.y - r, 2 * r, 2 * r)); ctx.restoreGState()
}

func paper() {
    fill(PAPER)
    glow(CGPoint(x: W * 0.78, y: H * 0.15), 900, rgb(0xF0752E, 0.10))
    glow(CGPoint(x: W * 0.1, y: H * 0.95), 700, rgb(0x0F766E, 0.06))
}

// MARK: - the desktop scene (shared by several scenes)

struct Thumb { let img: CGImage; let x: CGFloat; let y: CGFloat; let rot: CGFloat; let delay: CGFloat }
var rng = SystemRandomNumberGenerator()
let thumbs: [Thumb] = shots.enumerated().map { i, s in
    // Deterministic scatter over the left two thirds.
    let a = CGFloat((i * 7919) % 997) / 997, b = CGFloat((i * 104_729) % 991) / 991
    return Thumb(img: s, x: 70 + a * 1000, y: 260 + b * 420, rot: (CGFloat((i * 37) % 13) - 6) * .pi / 180, delay: CGFloat(i) * 0.022)
}
func folderSlot(_ i: Int) -> CGPoint { CGPoint(x: 110 + CGFloat(i) * 190, y: 790) }

// MARK: - scenes

typealias Scene = (start: CGFloat, end: CGFloat, draw: (CGFloat) -> Void)   // draw gets absolute time t

let intro: Scene = (0, 4.2, { t in
    fill(NIGHT)
    glow(CGPoint(x: W / 2, y: H / 2 - 40), 300 + 500 * easeOut(seg(t, 0, 2)), rgb(0xF0752E, 0.30))
    let k = spring(seg(t, 0.15, 1.3))
    image(logo, W / 2 - 130, 250, width: 260, alpha: clamp(k * 2), radius: 0, shadow: 0.6, rotate: (1 - k) * -0.25, scale: 0.4 + 0.6 * k)
    let w1 = easeOut(seg(t, 1.0, 1.7))
    let wordW: CGFloat = 520
    text("Sparehand", W / 2 - wordW / 2 - 40, 560 + (1 - w1) * 30, size: 112, weight: .bold, color: rgb(0xFFFFFF), alpha: w1, rounded: true, kern: -2)
    let v = spring(seg(t, 1.5, 2.3))
    pill("1.0", W / 2 + wordW / 2 + 10, 588 + (1 - v) * 20, size: 34, fg: rgb(0xFFFFFF), bg: ORANGE, alpha: clamp(v * 1.5))
    text("A spare pair of hands for your Mac.", W / 2, 730 + (1 - easeOut(seg(t, 1.9, 2.5))) * 18, size: 38, weight: .medium,
         color: rgb(0xFFFFFF, 0.7), alpha: easeOut(seg(t, 1.9, 2.5)), center: true)
    // Light wipe into the product.
    let wipe = easeInOut(seg(t, 3.5, 4.2))
    if wipe > 0 {
        ctx.saveGState()
        let r = wipe * 1300
        ctx.addEllipse(in: R(W / 2 - r, 380 - r, 2 * r, 2 * r)); ctx.clip()
        paper()
        ctx.restoreGState()
    }
})

let messy: Scene = (4.2, 8.8, { t in
    paper()
    for th in thumbs {
        let k = back(seg(t, 4.4 + th.delay * 0.8, 4.9 + th.delay * 0.8))
        image(th.img, th.x, th.y, width: 170, alpha: clamp(k * 3), radius: 6, shadow: 0.35, rotate: th.rot, scale: 0.5 + 0.5 * k)
    }
    // Downloads: the installers.
    let d = easeOut(seg(t, 5.2, 5.9))
    let dx = 1230 + (1 - d) * 80
    ctx.saveGState(); ctx.setAlpha(d)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0, 0.14))
    ctx.addPath(CGPath(roundedRect: R(dx, 640, 560, 330), cornerWidth: 18, cornerHeight: 18, transform: nil)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    text("Downloads", dx + 28, 664, size: 22, weight: .semibold, color: INK, alpha: d)
    for (i, n) in installers.prefix(6).enumerated() {
        let k = easeOut(seg(t, 5.5 + CGFloat(i) * 0.08, 5.9 + CGFloat(i) * 0.08))
        image(n.hasSuffix(".pkg") ? pkgIcon : dmgIcon, dx + 30, 710 + CGFloat(i) * 42, width: 36, alpha: k, shadow: 0)
        text(n, dx + 80, 716 + CGFloat(i) * 42, size: 19, weight: .regular, color: BODY, alpha: k)
    }
    // The browser with the trip tabs.
    let b = easeOut(seg(t, 5.8, 6.6))
    image(tabs.first, 1150 + (1 - b) * 200, 150, width: 700, alpha: b, radius: 14)
    caption("Your Mac, on a normal day.", "80 screenshots. Old installers. Five tabs you'll get back to.", t: t, start: 4.6, end: 8.8, y: 90)
})

let notices: Scene = (8.8, 13.4, { t in
    messy.draw(8.79)    // the scene behind, frozen
    let dim = easeOut(seg(t, 8.8, 9.3))
    ctx.saveGState(); ctx.setFillColor(rgb(0xF7F6F3, 0.88 * dim)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)); ctx.restoreGState()
    glow(CGPoint(x: 1500, y: 540), 700, rgb(0xF0752E, 0.10 * dim))
    let k = spring(seg(t, 9.0, 10.0))
    let cw: CGFloat = 660
    let ch = imageHeight(cards, width: cw)
    let cx = 1160 + (1 - k) * 760, cy = (H - ch) / 2
    image(cards, cx, cy, width: cw, alpha: clamp(k * 2), shadow: 0)
    // Light each card in turn (three equal bands of the stack).
    for i in 0..<3 {
        let s = 10.4 + CGFloat(i) * 0.8
        let a = easeOut(seg(t, s, s + 0.25)) * (1 - easeOut(seg(t, s + 0.7, s + 0.95)))
        let band = (ch - 30) / 3
        spotlight(CGRect(x: cx + 16, y: cy + 16 + CGFloat(i) * band, width: cw - 32, height: band - 14), alpha: a)
    }
    caption("Sparehand noticed three things.", "Nobody told it what to look for.", t: t, start: 9.2, end: 13.4, y: 400)
})

let details: Scene = (13.4, 19.4, { t in
    paper()
    let img = sortDetail ?? dashForYou
    let k = easeOut(seg(t, 13.4, 14.1))
    let w: CGFloat = 1380, h = imageHeight(img, width: w)
    let x = (W - w) / 2, y = (H - h) / 2 + 60
    let z = easeInOut(seg(t, 15.0, 16.1))
    // The window recedes a little while its detail pane comes forward.
    image(img, x - z * 160, y + z * 20, width: w, alpha: k * (1 - 0.86 * z), radius: 16, scale: (0.92 + 0.08 * k) * (1 - 0.08 * z))
    if let img, z > 0, let pane = img.cropping(to: CGRect(x: CGFloat(img.width) * 0.508, y: 0, width: CGFloat(img.width) * 0.492, height: CGFloat(img.height))) {
        let fromW = w * 0.492, fromX = x + w * 0.508, fromY = y
        let toW: CGFloat = 700, toH = imageHeight(pane, width: toW)
        let toX: CGFloat = 1080, toY = (H - toH) / 2 + 20
        image(pane, lerp(fromX, toX, z), lerp(fromY, toY, z), width: lerp(fromW, toW, z), radius: 16, shadow: z)
    }
    caption("Every offer says exactly what it will do.", nil, t: t, start: 13.6, end: 15.1, y: 60)
    caption("What happens, why now, the steps.", "You read it before you agree.", t: t, start: 16.0, end: 19.4, x: 130, y: 470)
})

let sorting: Scene = (19.4, 26.4, { t in
    paper()
    let n = min(folders.count, 6)
    for i in 0..<n {
        let p = folderSlot(i)
        let k = back(seg(t, 19.6 + CGFloat(i) * 0.06, 20.1 + CGFloat(i) * 0.06))
        image(folderIcon, p.x, p.y, width: 130, alpha: clamp(k * 2), shadow: 0.2, scale: 0.6 + 0.4 * k)
        text(folders[i].0, p.x + 65, p.y + 140, size: 20, weight: .semibold, color: INK, alpha: clamp(k * 2), center: true)
    }
    // Thumbnails fly into folders along arcs, in real-run order of magnitude.
    var landed = [Int](repeating: 0, count: max(n, 1))
    for (i, th) in thumbs.enumerated() {
        let f = n == 0 ? 0 : i % n
        let s = 20.4 + CGFloat(i) * 0.045
        let k = easeInOut(seg(t, s, s + 0.7))
        if k >= 1 { landed[f] += 1; continue }
        let dest = CGPoint(x: folderSlot(f).x + 35, y: folderSlot(f).y + 30)
        let mid = CGPoint(x: (th.x + dest.x) / 2, y: min(th.y, dest.y) - 160)
        let a = lerpPt(lerpPt(CGPoint(x: th.x, y: th.y), mid, k), lerpPt(mid, dest, k), k)
        image(th.img, a.x, a.y, width: lerp(170, 50, k), alpha: 1 - k * 0.3, radius: 6, shadow: 0.3, rotate: th.rot * (1 - k))
    }
    for i in 0..<n where landed[i] > 0 {
        pill("\(min(landed[i], folders[i].1 > 0 ? folders[i].1 : landed[i]))", folderSlot(i).x + 100, folderSlot(i).y - 14, size: 18, fg: rgb(0xFFFFFF), bg: TEAL)
    }
    // The real card, live.
    let ci = sortCards.isEmpty ? nil : sortCards[min(sortCards.count - 1, Int(seg(t, 20.4, 24.5) * CGFloat(sortCards.count - 1)))]
    let card = t < 24.8 ? ci : (sortDone ?? ci)
    let cin = easeOut(seg(t, 19.8, 20.4))
    image(card, 1300 + (1 - cin) * 300, 250, width: 520, alpha: cin, shadow: 0)
    ripple(CGPoint(x: 1395, y: 405), seg(t, 20.0, 20.6))
    caption("Sorted by what's in them.", "\(sortedCount) screenshots into \(n) folders. In the background, while you work.", t: t, start: 19.7, end: 26.4, y: 80)
})

let beforeAfter: Scene = (26.4, 30.0, { t in
    paper()
    let h: CGFloat = 760, w = h * CGFloat(desktopBefore?.width ?? 16) / CGFloat(desktopBefore?.height ?? 10)
    let x = (W - w) / 2, y: CGFloat = 250
    let k = easeOut(seg(t, 26.4, 26.9))
    image(desktopBefore, x, y, width: w, alpha: k, radius: 14)
    let p = easeInOut(seg(t, 27.0, 28.5))
    if p > 0 {
        ctx.saveGState(); ctx.clip(to: R(x, y - 10, w * p, h + 20))
        image(sortedAfter, x, y, width: w, radius: 14, shadow: 0)
        ctx.restoreGState()
        ctx.setFillColor(rgb(0xF0752E)); ctx.fill(R(x + w * p - 2, y - 16, 4, h + 32))
        ctx.fillEllipse(in: R(x + w * p - 14, y + h / 2 - 14, 28, 28))
    }
    pill("Before", x + 20, y - 58, size: 18, fg: rgb(0xFFFFFF), bg: MUTED, alpha: k)
    pill("After", x + w - 110, y - 58, size: 18, fg: rgb(0xFFFFFF), bg: TEAL, alpha: easeOut(seg(t, 27.6, 28.0)))
    let kept = shots.count - (Int(sortedCount) ?? shots.count)
    caption("Before and after.", "\(sortedCount) screenshots, now in \(folders.count) folders named for what's inside." + (kept > 0 ? " Your \(kept) newest stayed put." : ""), t: t, start: 26.5, end: 30.0, y: 70)
})

let binning: Scene = (26.4, 30.6, { t in
    paper()
    let trash = CGPoint(x: 820, y: 520)
    let done = t > 28.6
    image(done ? trashFull : trashEmpty, trash.x, trash.y, width: 230, shadow: 0.25, scale: 1 + 0.06 * sin(seg(t, 28.4, 28.9) * .pi))
    for (i, n) in installers.prefix(6).enumerated() {
        let s = 26.9 + CGFloat(i) * 0.25
        let k = easeInOut(seg(t, s, s + 0.7))
        let start = CGPoint(x: 160 + CGFloat(i) * 110, y: 330 + CGFloat(i % 2) * 70)
        let p = lerpPt(start, CGPoint(x: trash.x + 70, y: trash.y + 40), k)
        image(n.hasSuffix(".pkg") ? pkgIcon : dmgIcon, p.x, p.y - sin(k * .pi) * 120, width: lerp(110, 50, k), alpha: 1 - k * 0.8, shadow: 0.2)
        if k < 0.05 { text(n, start.x + 55, start.y + 118, size: 15, weight: .medium, color: MUTED, center: true) }
    }
    let c = easeOut(seg(t, 28.6, 29.4))
    text("Freed \(freed)", trash.x + 115, trash.y + 270, size: 52, weight: .bold, color: TEAL, alpha: c, rounded: true, center: true)
    let dIn = easeOut(seg(t, 26.6, 27.2)), swap = easeInOut(seg(t, 28.4, 28.9))
    image(downloadsBefore, 1240, 260, width: 600, alpha: dIn * (1 - swap), radius: 14)
    image(downloadsAfter, 1240, 260, width: 600, alpha: dIn * swap, radius: 14)
    pill(swap < 0.5 ? "Downloads · before" : "Downloads · after", 1540, 214, size: 17, fg: rgb(0xFFFFFF), bg: swap < 0.5 ? MUTED : TEAL, alpha: dIn, center: true)
    caption("Clears what you don't need.", "Old installers to the Bin. One click undoes it.", t: t, start: 26.6, end: 30.6, y: 80)
})

let research: Scene = (30.6, 44.6, { t in
    paper()
    // Left: the browser. Right: Sparehand's own screen, where Notes is written.
    let bx: CGFloat = 80, by: CGFloat = 250, bw: CGFloat = 820
    let tabIndex = min(4, max(0, Int((t - 32.2) / 1.0)))
    let bIn = easeOut(seg(t, 30.6, 31.3)), bOut = 1 - easeOut(seg(t, 42.0, 42.8))
    image(tabs.isEmpty ? nil : tabs[tabIndex], bx, by, width: bw, alpha: bIn * bOut, radius: 14)
    // Sparehand's screen.
    let sx: CGFloat = 980, sy: CGFloat = 210, sw: CGFloat = 860, sh: CGFloat = 560
    let sIn = easeOut(seg(t, 31.0, 31.8))
    let grow = easeInOut(seg(t, 42.2, 43.3))
    let fx = lerp(sx, 260, grow), fy = lerp(sy, 170, grow), fw = lerp(sw, 1400, grow), fh = fw * sh / sw
    ctx.saveGState(); ctx.setAlpha(sIn)
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: rgb(0, 0.25))
    ctx.addPath(CGPath(roundedRect: R(fx, fy, fw, fh), cornerWidth: 22, cornerHeight: 22, transform: nil)); ctx.setFillColor(rgb(0x1C1C21)); ctx.fillPath()
    ctx.restoreGState()
    pill("Sparehand's own screen", fx + fw / 2, fy - 54, size: 18, fg: rgb(0xFFFFFF), bg: rgb(0x0F766E), alpha: sIn, center: true)
    if !noteFrames.isEmpty {
        let i = min(noteFrames.count - 1, Int(seg(t, 32.4, 41.6) * CGFloat(noteFrames.count - 1)))
        let n = noteFrames[i]
        let inner = CGRect(x: fx + 18, y: fy + 18, width: fw - 36, height: fh - 36)
        let nw = min(inner.width, inner.height * CGFloat(n.width) / CGFloat(n.height))
        image(n, inner.midX - nw / 2, inner.minY + (inner.height - imageHeight(n, width: nw)) / 2, width: nw, alpha: sIn, radius: 10, shadow: 0)
    }
    // Each tab lifts out of the tab strip and flies into the note.
    if let strip = tabs.first {
        let tabRanges: [(CGFloat, CGFloat)] = [(205, 590), (620, 1043), (1069, 1472), (1504, 1907), (1933, 2342)]
        for (i, r) in tabRanges.enumerated() {
            let s = 32.2 + CGFloat(i) * 1.0
            let k = easeInOut(seg(t, s, s + 0.9))
            guard k > 0, k < 1, let chip = strip.cropping(to: CGRect(x: r.0, y: 0, width: r.1 - r.0, height: 80)) else { continue }
            let scale = bw / CGFloat(strip.width)
            let from = CGPoint(x: bx + r.0 * scale, y: by)
            let to = CGPoint(x: sx + 120, y: sy + 120 + CGFloat(i) * 60)
            let mid = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - 140)
            let p = lerpPt(lerpPt(from, mid, k), lerpPt(mid, to, k), k)
            image(chip, p.x, p.y, width: (r.1 - r.0) * scale * lerp(1.25, 0.9, k), alpha: 1 - easeOut(seg(k, 0.85, 1)), radius: 8, shadow: 0.6, scale: 1 + 0.15 * sin(k * .pi))
        }
    }
    caption("Big jobs run on its own screen.", "It read your five tabs and wrote the trip plan in Notes. You kept working.", t: t, start: 30.9, end: 42.0, y: 70)
    caption("A plan you can pick up later.", nil, t: t, start: 43.2, end: 44.6, x: 260, y: 60)
})

let undo: Scene = (44.6, 48.2, { t in
    paper()
    let k = easeOut(seg(t, 44.6, 45.3))
    let w: CGFloat = 1300, h = imageHeight(today, width: w)
    let x = (W - w) / 2, y = (H - h) / 2 + 50
    image(today, x, y + (1 - k) * 40, width: w, alpha: k, radius: 16)
    let s = easeOut(seg(t, 45.6, 46.0))
    spotlight(CGRect(x: x + w * 0.86, y: y + h * 0.12, width: w * 0.13, height: h * 0.36), alpha: s * 0.8, radius: 12)
    caption("Undo anything.", "Every change is recorded. Files move back, notes are removed.", t: t, start: 44.8, end: 48.2, y: 60)
})

let learns: Scene = (48.2, 51.8, { t in
    paper()
    for (i, th) in thumbs.prefix(8).enumerated() {
        let k = back(seg(t, 48.3 + CGFloat(i) * 0.08, 48.8 + CGFloat(i) * 0.08))
        image(th.img, 160 + CGFloat(i % 4) * 190, 380 + CGFloat(i / 4) * 170, width: 150, alpha: clamp(k * 2), radius: 6, shadow: 0.35, rotate: th.rot, scale: 0.5 + 0.5 * k)
    }
    let k = spring(seg(t, 49.2, 50.2))
    image(repeatCards, 1180 + (1 - k) * 500, 330, width: 600, alpha: clamp(k * 2), shadow: 0)
    caption("Approve once. It handles the repeat.", "New screenshots, sorted the way you liked last time.", t: t, start: 48.4, end: 51.8, y: 90)
})

let outro: Scene = (51.8, 57.0, { t in
    fill(NIGHT)
    glow(CGPoint(x: W / 2, y: 360), 700, rgb(0xF0752E, 0.28 * easeOut(seg(t, 51.8, 53))))
    let k = spring(seg(t, 51.9, 52.9))
    image(logo, W / 2 - 100, 200, width: 200, alpha: clamp(k * 2), shadow: 0.5, scale: 0.6 + 0.4 * k)
    let a = easeOut(seg(t, 52.4, 53.0))
    text("Sparehand 1.0", W / 2, 450, size: 86, weight: .bold, color: rgb(0xFFFFFF), alpha: a, rounded: true, center: true, kern: -1.5)
    text("Asks first  ·  Undo anything  ·  Your files never leave your Mac", W / 2, 580, size: 32, weight: .medium, color: rgb(0xFFFFFF, 0.72),
         alpha: easeOut(seg(t, 53.0, 53.6)), center: true)
    pill("github.com/pulkitnagpal/sparehand", W / 2, 680, size: 26, fg: rgb(0xFFFFFF), bg: ORANGE, alpha: easeOut(seg(t, 53.5, 54.1)), center: true)
    let fade = easeInOut(seg(t, 56.3, 57.0))
    if fade > 0 { ctx.setFillColor(rgb(0, fade)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
})

func shifted(_ s: Scene, _ by: CGFloat) -> Scene { (s.start + by, s.end + by, { t in s.draw(t - by) }) }
let gap: CGFloat = 3.6
let scenes: [Scene] = [intro, messy, notices, details, sorting, beforeAfter] + [binning, research, undo, learns, outro].map { shifted($0, gap) }
let total = scenes.last!.end

// MARK: - render

let bytesPerRow = Int(W) * 4
var buffer = [UInt8](repeating: 0, count: bytesPerRow * Int(H))
let out = FileHandle.standardOutput
let frameCount = Int(total * FPS)
FileHandle.standardError.write(Data("assets: shots \(shots.count) tabs \(tabs.count) notes \(noteFrames.count) sortCards \(sortCards.count) folders \(folders.map(\.0))\n".utf8))
for f in 0..<frameCount {
    let t = CGFloat(Double(f) / FPS)
    buffer.withUnsafeMutableBytes { raw in
        ctx = CGContext(data: raw.baseAddress, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let scene = scenes.first(where: { t >= $0.start && t < $0.end }) ?? scenes.last else { return }
        scene.draw(t)
        // A short crossfade from the previous scene keeps cuts soft.
        if let i = scenes.firstIndex(where: { $0.start == scene.start }), i > 0, t - scene.start < 0.25, scenes[i - 1].end == scene.start, i != 1 {
            let k = (t - scene.start) / 0.25
            ctx.saveGState(); ctx.setAlpha(1 - easeOut(k))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil); scenes[i - 1].draw(scene.start - 0.001); ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }
    buffer.withUnsafeBytes { out.write(Data($0)) }
    if f % 60 == 0 { FileHandle.standardError.write(Data("frame \(f)/\(frameCount)\n".utf8)) }
}
