import AppKit
import SparehandCore
import SwiftUI

/// Quiet while a call app is in front or the front window fills the screen.
struct DesktopQuietRules: QuietRules {
    static let callApps: Set<String> = ["us.zoom.xos", "com.apple.FaceTime", "com.microsoft.teams2"]

    func isQuiet() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if Self.callApps.contains(front.bundleIdentifier ?? "") { return true }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let w = list.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
        let frame = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        return NSScreen.screens.contains { s in
            let d = CGDisplayBounds((s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0)
            return d.width > 0 && frame.equalTo(d)
        }
    }
}

enum Paths {
    /// The bundled `sparehand` CLI (Contents/Resources in the app; next to the binary during development).
    static var cli: URL {
        if let u = Bundle.main.url(forResource: "sparehand", withExtension: nil) { return u }
        return Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("sparehand")
    }

    static var judgeScript: URL? {
        if let u = Bundle.main.url(forResource: "judge-server", withExtension: "sh") { return u }
        let dev = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("../../scripts/judge-server.sh").standardized
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var pending: [Tap] = []
    @Published var done: [Tap] = []
    @Published var pausedUntil: Date?
    @Published var judgeStatus = "Checking the local model…"
    @Published var busyTapID: String?

    let store: Store
    let env: SparehandCore.Environment
    let screen = AgentScreen()
    private(set) var engine: Engine!
    private var timer: Timer?
    private var watchers: [DispatchSourceFileSystemObject] = []
    lazy var tapPanel = TapPanel(model: self)

    init() {
        do { store = try Store(path: SparehandCore.Environment.supportDirectory.appendingPathComponent("sparehand.sqlite")) }
        catch { fatalError("Sparehand can't open its database: \(error)") }
        env = SparehandCore.Environment.live(store: store)
        engine = Engine(env: env,
                        watchers: [ScreenshotsWatcher(), BinWatcher(), TabsWatcher()],
                        judge: FallbackJudge(primary: LocalModelJudge()),
                        quiet: DesktopQuietRules(),
                        jobs: WatchableJobRunner(model: self))
    }

    func start() {
        startJudge()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in await self.tick() } }
        watch(env.desktop)
        watch(env.trash)
        Task { await tick() }
    }

    var isPaused: Bool { (pausedUntil ?? .distantPast) > Date() }

    func pause(hours: Double) { pausedUntil = Date().addingTimeInterval(hours * 3600) }
    func resume() { pausedUntil = nil }

    func tick() async {
        await refreshFeed()
        guard !isPaused, busyTapID == nil else { return }
        let fresh = await engine.tick()
        await refreshFeed()
        if let first = fresh.first { tapPanel.show(first) }
    }

    func refreshFeed() async {
        let f = await engine.feed()
        pending = f.pending
        done = f.done
    }

    func approve(_ tap: Tap) {
        if case .deletePermanently(let urls) = tap.candidate.plan {
            let alert = NSAlert()
            alert.messageText = "Empty \(urls.count) \(urls.count == 1 ? "item" : "items") from the Bin?"
            alert.informativeText = urls.map(\.lastPathComponent).joined(separator: "\n") + "\n\nThis can't be undone."
            alert.addButton(withTitle: "Empty \(urls.count)")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        tapPanel.hide()
        busyTapID = tap.id
        Task {
            _ = await engine.approve(tap.id)
            busyTapID = nil
            await refreshFeed()
        }
    }

    func dismiss(_ tap: Tap) {
        tapPanel.hide()
        Task { await engine.dismiss(tap.id); await refreshFeed() }
    }

    func undo(_ tap: Tap) {
        Task { _ = await engine.undo(tap.id); await refreshFeed() }
    }

    // MARK: - Judge server

    func startJudge() {
        guard let script = Paths.judgeScript else { judgeStatus = "Local model script missing: using simple rules"; return }
        judgeStatus = "Starting the local model (first time downloads it)…"
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [script.path, "start"]
            let out = Pipe(); p.standardOutput = out; p.standardError = out
            try? p.run(); p.waitUntilExit()
            let ok = p.terminationStatus == 0
            await MainActor.run { self.judgeStatus = ok ? "Local model ready" : "Local model unavailable: using simple rules" }
        }
    }

    // MARK: - Folder watching

    private func watch(_ dir: URL) {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }   // e.g. the Bin without Full Disk Access
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        var pendingTick: DispatchWorkItem?
        src.setEventHandler { [weak self] in
            pendingTick?.cancel()
            let item = DispatchWorkItem { Task { @MainActor in await self?.tick() } }
            pendingTick = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers.append(src)
    }
}
