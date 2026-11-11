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
    @Published var localReady = false

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
        // --demo: for walkthroughs and recordings. No card limits or quiet times, and new files are looked at within seconds.
        var limits = Limits()
        if Self.demo { limits.perHour = 99; limits.perDay = 99; limits.idleSeconds = .infinity }
        engine = Engine(env: env, senses: Senses(env: env), local: LocalModel(), claude: claude,
                        quiet: Self.demo ? NeverQuiet() as any QuietRules : DesktopQuietRules(), limits: limits)
    }

    static let demo = CommandLine.arguments.contains("--demo")

    func start() {
        // A job that was running when Sparehand last quit didn't finish.
        for var t in (try? store.taps(states: [.running])) ?? [] { t.state = .failed; t.note = "Interrupted when Sparehand quit."; try? store.upsert(t) }
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
        // "Look now" also brings back cards that are still waiting.
        let waiting = force ? pending.filter { p in !r.taps.contains { $0.id == p.id } } : []
        if !(r.taps + waiting).isEmpty { tapPanel.show(r.taps + waiting) }
    }

    func refreshFeed() async {
        let f = await engine.feed()
        pending = f.pending
        done = f.done
    }

    func approve(_ tap: Tap) {
        tapPanel.set(tap, .working(tap.candidate.steps.contains { WatchableRun.fileTools.contains($0.tool) } ? "Starting on Sparehand's screen…" : "Starting…"))
        busyTapID = tap.id
        Task {
            let result = await runner.run(tap) { [weak self] line in self?.tapPanel.set(tap, .working(line)) }
            busyTapID = nil
            if let r = result {
                tapPanel.set(r, r.state == .failed ? .failed(r.note ?? "Something went wrong.") : .done(r.note ?? "Done"))
            } else {
                tapPanel.set(tap, .failed("That suggestion no longer exists."))
            }
            tapPanel.removeLater(tap.id, after: 10)
            await refreshFeed()
        }
    }

    func dismiss(_ tap: Tap) {
        tapPanel.remove(tap.id)
        Task { await engine.dismiss(tap.id); await refreshFeed() }
    }

    func never(_ tap: Tap) {
        tapPanel.set(tap, .undone("Won't offer this again."))
        tapPanel.removeLater(tap.id, after: 3)
        Task { await engine.never(tap.id); await refreshFeed() }
    }

    func undo(_ tap: Tap) {
        tapPanel.set(tap, .working("Putting it back…"))
        Task {
            let r = await engine.undo(tap.id)
            tapPanel.set(r ?? tap, r?.state == .undone ? .undone(r?.note ?? "Put back") : .failed(r?.note ?? "Couldn't undo."))
            tapPanel.removeLater(tap.id, after: 6)
            await refreshFeed()
        }
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
            await MainActor.run { self.localReady = ok; self.status = (ok ? "Local model ready" : "Local model unavailable") + " · \(cloud)" }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + (Self.demo ? 3 : 20), execute: item)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers.append(src)
    }
}
