import AppKit
import SparehandCore

/// Filming mode (`--film <dir>`): runs the real product through the demo storyline and captures Sparehand's own windows
/// (the cards, the main window, and Notes on Sparehand's screen) by window number, so nothing else on screen is filmed.
/// Every card, plan and result is real; the director only clicks for you and keeps time.
@MainActor
final class FilmDirector {
    let model: AppModel
    let delegate: AppDelegate
    let dir: URL
    var log: [[String: Any]] = []
    let t0 = Date()

    init(model: AppModel, delegate: AppDelegate, dir: URL) {
        self.model = model; self.delegate = delegate; self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func mark(_ event: String, _ extra: [String: Any] = [:]) {
        var e = extra; e["t"] = Date().timeIntervalSince(t0); e["event"] = event
        log.append(e)
        print("[film] \(event)")
    }

    @discardableResult
    func capture(_ name: String, window: Int?) -> Bool {
        guard let window, window > 0 else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", "\(window)", dir.appendingPathComponent(name + ".png").path]
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    /// Captures `windows` repeatedly while Sparehand is busy with a card.
    func roll(_ prefix: String, windows: [String: () -> Int?]) async {
        var i = 0
        let start = Date()
        while model.busyTapID != nil && Date().timeIntervalSince(start) < 300 {
            for (name, w) in windows { capture(String(format: "%@-%@-%04d", prefix, name, i), window: w()) }
            i += 1
            try? await Task.sleep(for: .milliseconds(250))
        }
        mark("\(prefix) frames", ["count": i])
    }

    var dashboard: Int? { delegate.dashboardWindowNumber }
    var cards: Int? { model.tapPanel.windowNumber }
    var notes: Int? { Self.window(owner: "Notes", inside: model.screen.bounds, minHeight: 300) }
    var livePanel: Int? { Self.window(owner: ProcessInfo.processInfo.processName, width: 480) }

    static func window(owner: String, inside: CGRect? = nil, minHeight: CGFloat = 0, width: CGFloat? = nil) -> Int? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list where (w[kCGWindowOwnerName as String] as? String) == owner {
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if let inside, !inside.contains(CGPoint(x: r.midX, y: r.midY)) { continue }
            if r.height < minHeight { continue }
            if let width, abs(r.width - width) > 2 { continue }
            return w[kCGWindowNumber as String] as? Int
        }
        return nil
    }

    func first(_ tool: String) -> Tap? { model.pending.first { $0.candidate.steps.contains { $0.tool == tool } } }

    func act(_ tap: Tap, _ prefix: String) async {
        model.section = .forYou
        model.selectedOfferID = tap.id
        await pause(1.0)
        capture("\(prefix)-detail", window: dashboard)
        mark("\(prefix) detail", ["title": tap.verdict.title, "benefit": tap.candidate.benefit ?? ""])
        model.approve(tap)
        var windows: [String: () -> Int?] = ["dash": { self.dashboard }, "card": { self.cards }]
        if tap.candidate.steps.contains(where: { WatchableRun.watched.contains($0.tool) }) {
            windows["notes"] = { self.notes }
            windows["live"] = { self.livePanel }
        }
        await roll(prefix, windows: windows)
        await pause(0.6)
        capture("\(prefix)-done-dash", window: dashboard)
        capture("\(prefix)-done-card", window: cards)
        mark("\(prefix) done", ["note": model.done.first { $0.id == tap.id }?.note ?? ""])
    }

    func run() async {
        mark("start")
        await pause(3)
        // Sparehand looks every few minutes; filming takes up to three looks so every offer is waiting together.
        for attempt in 0..<3 where model.pending.count < 3 {
            await model.look(force: true)
            mark("look \(attempt + 1)", ["titles": model.pending.map(\.verdict.title)])
            await pause(1.0)
        }
        await pause(1.5)
        capture("cards", window: cards)
        mark("cards", ["titles": model.pending.map(\.verdict.title), "benefits": model.pending.map { $0.candidate.benefit ?? "" }])

        delegate.showDashboard()
        // Film on a Retina screen when there is one, so captures are sharp.
        if let retina = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }), let w = delegate.dashboardWindow {
            let f = retina.visibleFrame
            w.setFrame(NSRect(x: f.midX - 520, y: f.midY - 330, width: 1040, height: 660), display: true)
        }
        await pause(1.5)
        capture("dash-for-you", window: dashboard)

        if let t = first("sort_by_content") ?? first("organize_files") { await act(t, "sort") }
        if let t = first("move_to_bin") { await act(t, "bin") }
        if let t = first("research_to_note") { await act(t, "note") }

        model.section = .today
        await pause(1.0)
        capture("dash-today", window: dashboard)
        model.section = .learned
        await pause(1.0)
        capture("dash-learned", window: dashboard)

        // The repeat: new screenshots arrive, and the learned skill offers to sort them.
        let cli = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("sparehand").path
        _ = Shell.run(FileManager.default.isExecutableFile(atPath: cli) ? cli : Bundle.main.path(forResource: "sparehand", ofType: nil) ?? cli,
                      ["demo-seed", "8"], env: ProcessInfo.processInfo.environment, timeout: 60)
        await pause(1.0)
        await model.look(force: true)
        await pause(1.5)
        capture("repeat-cards", window: cards)
        model.section = .forYou
        await pause(1.0)
        capture("repeat-dash", window: dashboard)
        mark("repeat", ["titles": model.pending.map(\.verdict.title)])

        mark("done")
        if let data = try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted]) {
            try? data.write(to: dir.appendingPathComponent("film.json"))
        }
        print("[film-done]")
    }
}
