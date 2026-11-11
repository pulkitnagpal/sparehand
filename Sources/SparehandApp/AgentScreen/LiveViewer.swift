import AppKit
import CoreMedia
import ScreenCaptureKit
import SwiftUI

struct LiveStep: Identifiable, Equatable {
    enum State { case done, current, pending }
    let id: Int
    let text: String
    var state: State
}

/// Streams only the windows Sparehand opened on its own screen, at up to 30 fps, into a layer the views show.
@MainActor
final class LiveViewer: ObservableObject {
    @Published var steps: [LiveStep] = []
    @Published var status = "Getting Sparehand's screen ready…"
    @Published var needsYou = false
    /// One layer per view showing the stream (the picture-in-picture panel and the full-screen window).
    private var layers: [CALayer] = []

    var onPause: (() -> Void)?
    var onStop: (() -> Void)?

    private let screen: AgentScreen
    private var stream: SCStream?
    private var output: FrameOutput?
    private var windowIDs: [CGWindowID] = []
    private var panel: NSPanel?
    private var fullWindow: NSWindow?

    init(screen: AgentScreen) {
        self.screen = screen
    }

    func makeLayer() -> CALayer {
        let l = CALayer()
        l.contentsGravity = .resizeAspect
        l.backgroundColor = StreamColors.well
        l.contents = layers.first?.contents
        layers.append(l)
        return l
    }

    fileprivate func show(_ surface: IOSurface) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in layers { l.contents = surface }
        CATransaction.commit()
    }

    func setSteps(_ texts: [String]) {
        steps = texts.enumerated().map { LiveStep(id: $0.offset, text: $0.element, state: $0.offset == 0 ? .current : .pending) }
    }

    /// Marks step `index` current and everything before it done.
    func advance(to index: Int) {
        for i in steps.indices { steps[i].state = i < index ? .done : (i == index ? .current : .pending) }
    }

    func finishSteps() {
        for i in steps.indices { steps[i].state = .done }
    }

    func start(windowIDs: [CGWindowID]) async throws {
        self.windowIDs = windowIDs
        let filter = try await makeFilter()
        let cfg = SCStreamConfiguration()
        cfg.width = 1920
        cfg.height = 1080
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.queueDepth = 5
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.backgroundColor = StreamColors.well
        let out = FrameOutput { [weak self] surface in self?.show(surface) }
        let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try s.addStreamOutput(out, type: .screen, sampleHandlerQueue: DispatchQueue(label: "dev.sparehand.frames"))
        try await s.startCapture()
        stream = s
        output = out
        showPanel()
    }

    /// Adds another of Sparehand's windows (for example Notes) to the picture.
    func add(windowID: CGWindowID) async throws {
        guard !windowIDs.contains(windowID) else { return }
        windowIDs.append(windowID)
        try await stream?.updateContentFilter(makeFilter())
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        output = nil
        panel?.close(); panel = nil
        fullWindow?.close(); fullWindow = nil
    }

    private func makeFilter() async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else {
            throw AgentScreen.Failure.didNotAppear
        }
        let mine = content.windows.filter { windowIDs.contains($0.windowID) }
        return SCContentFilter(display: display, including: mine)
    }

    // MARK: - Windows

    private func showPanel() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 470),
                        styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: LivePanelView(viewer: self, compact: true))
        if let main = NSScreen.screens.first {
            let f = main.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - 480 - 24, y: f.minY + 24))
        }
        p.orderFrontRegardless()
        panel = p
    }

    func watchFullScreen() {
        if fullWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Sparehand — live"
            w.collectionBehavior = [.fullScreenPrimary]
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: LivePanelView(viewer: self, compact: false))
            fullWindow = w
        }
        fullWindow?.center()
        fullWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        fullWindow?.toggleFullScreen(nil)
    }
}

/// Hands each captured frame's IOSurface to the viewer on the main thread.
final class FrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let deliver: @MainActor (IOSurface) -> Void
    init(deliver: @escaping @MainActor (IOSurface) -> Void) { self.deliver = deliver }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let px = CMSampleBufferGetImageBuffer(sb),
              let surface = CVPixelBufferGetIOSurface(px)?.takeUnretainedValue() else { return }
        nonisolated(unsafe) let s = surface
        DispatchQueue.main.async { MainActor.assumeIsolated { self.deliver(s) } }
    }
}
