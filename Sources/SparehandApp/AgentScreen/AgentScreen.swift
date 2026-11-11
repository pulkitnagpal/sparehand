import AppKit
import CVirtualDisplay

/// Sparehand's own invisible monitor. A fresh serial number every time, so macOS never puts
/// windows it remembers (possibly the user's) back on it.
@MainActor
final class AgentScreen {
    enum Failure: Error { case unavailable, didNotAppear }

    private var display: SHVirtualDisplay?
    private(set) var bounds: CGRect?
    var displayID: CGDirectDisplayID? { display.map { $0.displayID } }

    /// Creates the 1920×1080 screen and waits for macOS to place it. Returns its global bounds.
    func start() async throws -> CGRect {
        if let bounds { return bounds }
        let d = SHCreateVirtualDisplay(1920, 1080, UInt32.random(in: 1..<UInt32.max), "Sparehand")
        guard d.displayID != 0 else { throw Failure.unavailable }
        display = d
        for _ in 0..<40 {
            let b = CGDisplayBounds(d.displayID)
            if b.width > 0 { bounds = b; return b }
            try await Task.sleep(for: .milliseconds(100))
        }
        stop()
        throw Failure.didNotAppear
    }

    func stop() {
        if let display { SHDestroyVirtualDisplay(display) }
        display = nil
        bounds = nil
    }

    /// Where Sparehand puts the windows it works in.
    func workArea() -> CGRect {
        (bounds ?? .zero).insetBy(dx: 120, dy: 90)
    }
}
