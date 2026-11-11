import SwiftUI

/// Sparehand's light palette (design canvas). Hex values are fixed by the spec.
enum Theme {
    static let surface = Color(hex: 0xF7F6F3)
    static let card = Color.white
    static let well = Color(hex: 0xF4F2EE)
    static let ink = Color(hex: 0x16161A)
    static let body = Color(hex: 0x3F3F46)
    static let muted = Color(hex: 0x6B6B74)
    static let hairline = Color(hex: 0xE6E3DD)
    static let decide = Color(hex: 0xC2410C)
    static let decideSoft = Color(hex: 0xFDEBE1)
    static let decideDeep = Color(hex: 0x9A3412)
    static let working = Color(hex: 0x0F766E)
    static let workingSoft = Color(hex: 0xE3F1EF)
    static let pending = Color(hex: 0xD6D3CD)

    static func heading(_ size: CGFloat) -> Font {
        NSFont(name: "Space Grotesk", size: size) != nil ? .custom("Space Grotesk", size: size).weight(.semibold)
            : .system(size: size, weight: .semibold)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension NSColor {
    static let sparehandWell = NSColor(srgbRed: 0xF4 / 255, green: 0xF2 / 255, blue: 0xEE / 255, alpha: 1)
}

/// Held for the app's lifetime: ScreenCaptureKit copies the configuration's colour later, and a temporary
/// `NSColor.cgColor` can already be gone by then (crash in CGColorCreateCopy).
enum StreamColors {
    nonisolated(unsafe) static let well = CGColor(srgbRed: 0xF4 / 255, green: 0xF2 / 255, blue: 0xEE / 255, alpha: 1)
}
