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
    @Published var status = "Starting…"
    @Published var busyTapID: String?
    @Published var lastLook: [String] = []

    let store: Store
    let env: SparehandCore.Environment
    let screen = AgentScreen()
    let claude: ClaudeBackend?
    private(set) var engine: Engine!
    private var sampleTimer: Timer?
    private var lookTimer: Timer?
    private var watchers: [DispatchSourceFileSystemObject] = []
    lazy var tapPanel = TapPanel(model: self)
    lazy var runner = WatchableRun(model: self)

    init() {
        do { store = try Store(path: SparehandCore.Environment.supportDirectory.appendingPathComponent("sparehand-v1.sqlite")) }
        catch { fatalError("Sparehand can't open its database: \(error)") }
        env = SparehandCore.Environment.live(store: store)
        claude = Claude.fromKeychain()
        engine = Engine(env: env, senses: Senses(env: env), local: LocalModel(), claude: claude, quiet: DesktopQuietRules())
    }

    func start() {
        startLocalModel()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in await self.engine.sample() } }
        lookTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in Task { @MainActor in await self.look() } }
        watch(env.desktop)
        watch(env.home.appendingPathComponent("Downloads"))
        Task { await engine.sample(); await refreshFeed() }
    }

    var isPaused: Bool { (pausedUntil ?? .distantPast) > Date() }
    func pause(hours: Double) { pausedUntil = Date().addingTimeInterval(hours * 3600) }
    func resume() { pausedUntil = nil }

    /// One look at the Mac. `force` is the "Look now" button: it skips the quiet and limit checks.
    func look(force: Bool = false) async {
        guard force || !isPaused, busyTapID == nil else { return }
        let r = await engine.look(force: force)
        lastLook = r.steps
        await refreshFeed()
        if let first = r.taps.first { tapPanel.show(first) }
    }

    func refreshFeed() async {
        let f = await engine.feed()
        pending = f.pending
        done = f.done
    }

    func approve(_ tap: Tap) {
        tapPanel.hide()
        busyTapID = tap.id
        Task {
            _ = await runner.run(tap)
            busyTapID = nil
            await refreshFeed()
        }
    }

    func dismiss(_ tap: Tap) {
        tapPanel.hide()
        Task { await engine.dismiss(tap.id); await refreshFeed() }
    }

    func never(_ tap: Tap) {
        tapPanel.hide()
        Task { await engine.never(tap.id); await refreshFeed() }
    }

    func undo(_ tap: Tap) {
        Task { _ = await engine.undo(tap.id); await refreshFeed() }
    }

    // MARK: - Local model

    func startLocalModel() {
        let cloud = claude?.label ?? "no Claude connected"
        guard let script = Paths.judgeScript else { status = "Local model script missing · \(cloud)"; return }
        status = "Starting the local model… · \(cloud)"
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [script.path, "start"]
            let out = Pipe(); p.standardOutput = out; p.standardError = out
            try? p.run(); p.waitUntilExit()
            let ok = p.terminationStatus == 0
            await MainActor.run { self.status = (ok ? "Local model ready" : "Local model unavailable") + " · \(cloud)" }
        }
    }

    // MARK: - Folder watching: new files trigger an early look

    private func watch(_ dir: URL) {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        var pendingLook: DispatchWorkItem?
        src.setEventHandler { [weak self] in
            pendingLook?.cancel()
            let item = DispatchWorkItem { Task { @MainActor in await self?.look() } }
            pendingLook = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: item)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers.append(src)
    }
}
