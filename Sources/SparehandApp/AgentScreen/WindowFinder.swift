import AppKit

/// Finds a window's CGWindowID by its owner app and title, but only on Sparehand's screen.
enum WindowFinder {
    static func windowID(owner: String, title: String?, inside rect: CGRect) -> CGWindowID? {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list where (w[kCGWindowOwnerName as String] as? String) == owner && (w[kCGWindowLayer as String] as? Int) == 0 {
            if let title, (w[kCGWindowName as String] as? String) != title { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  rect.contains(CGPoint(x: (b["X"] ?? -1) + 1, y: (b["Y"] ?? -1) + 1)) else { continue }
            return w[kCGWindowNumber as String] as? CGWindowID
        }
        return nil
    }
}
