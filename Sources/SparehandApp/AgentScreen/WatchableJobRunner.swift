import AppKit
import SparehandCore

/// Runs "tabs → note" on Sparehand's own screen so the user can watch: Terminal with Claude Code, then Notes.
final class WatchableJobRunner: JobRunner, @unchecked Sendable {
    weak var model: AppModel?
    init(model: AppModel) { self.model = model }

    static let steps = ["Opened Terminal on Sparehand's screen", "Claude is reading the pages", "Making the table", "Putting it in Notes"]

    func runTabsToNote(tap: Tap) async throws -> String {
        guard case .tabsToNote(let topic, _) = tap.candidate.plan else { throw ClaudeJobError.failed("Not a tabs job") }
        guard let model = await MainActor.run(body: { self.model }) else { throw ClaudeJobError.failed("Sparehand is closing") }
        let screen = await MainActor.run { model.screen }
        let viewer = await MainActor.run { LiveViewer(screen: screen) }
        let scripts = OSAScriptRunner()
        let terminal = TerminalLauncher(runner: scripts)
        let notes = NotesWriter(runner: scripts)
        let jobs = SparehandCore.Environment.supportDirectory.appendingPathComponent("jobs", isDirectory: true)
        let htmlFile = jobs.appendingPathComponent("\(tap.id).html")
        let errorFile = jobs.appendingPathComponent("\(tap.id).error")
        try? FileManager.default.removeItem(at: htmlFile)
        try? FileManager.default.removeItem(at: errorFile)
        let match = "claude-run --job \(tap.id)"

        var terminalWindow: Int?
        func cleanUp() async {
            if let w = terminalWindow { try? await terminal.close(windowID: w) }
            await viewer.stop()
            await MainActor.run { screen.stop() }
        }

        do {
            let bounds = try await screen.start()
            let area = await MainActor.run { screen.workArea() }
            await MainActor.run {
                viewer.setSteps(Self.steps)
                viewer.status = "Starting Claude Code…"
                viewer.onStop = { Self.signal("TERM", match) }
                viewer.onPause = { Self.togglePause(match, viewer: viewer) }
            }
            let cli = Paths.cli.path
            let id = try await terminal.open(command: "clear; \(Self.shellQuote(cli)) claude-run --job \(tap.id); exit", title: "Sparehand · Claude Code")
            terminalWindow = id
            let left = CGRect(x: area.minX, y: area.minY, width: area.width * 0.58, height: area.height)
            try await terminal.setBounds(windowID: id, left)
            try await Task.sleep(for: .milliseconds(500))
            let cgID = CGWindowID(id)
            let windowID = WindowFinder.exists(cgID) ? cgID : (WindowFinder.windowID(owner: "Terminal", title: nil, inside: bounds) ?? cgID)
            try await viewer.start(windowIDs: [windowID])
            await MainActor.run { viewer.advance(to: 1); viewer.status = "Claude Code is reading \(topic.lowercased()) pages…" }

            // Wait for the CLI to leave its answer (or an error) in the jobs folder.
            var waited = 0.0
            while !FileManager.default.fileExists(atPath: htmlFile.path) {
                if let message = try? String(contentsOf: errorFile, encoding: .utf8) { throw ClaudeJobError.failed(message) }
                if waited > 600 { throw ClaudeJobError.failed("Claude took longer than 10 minutes") }
                try await Task.sleep(for: .milliseconds(500))
                waited += 0.5
            }
            await MainActor.run { viewer.advance(to: 2); viewer.status = "Table ready." }
            let table = try String(contentsOf: htmlFile, encoding: .utf8)

            await MainActor.run { viewer.advance(to: 3); viewer.status = "Creating the note…" }
            let notesRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty
            let before = await notes.userWindowCount(notesRunning: notesRunning)
            let noteID = try await notes.create(title: "\(topic), compared", html: table)
            if let nw = try? await notes.show(noteID: noteID, ifNoUserWindows: before) {
                let right = CGRect(x: area.minX + area.width * 0.42, y: area.minY + 40, width: area.width * 0.58, height: area.height - 40)
                try? await notes.setBounds(windowID: nw, right)
                try await Task.sleep(for: .milliseconds(600))
                if let cg = WindowFinder.windowID(owner: "Notes", title: nil, inside: bounds) { try? await viewer.add(windowID: cg) }
            }
            await MainActor.run { viewer.finishSteps(); viewer.status = "Done. The note is in Notes." }
            try await Task.sleep(for: .seconds(5))
            await cleanUp()
            return noteID
        } catch {
            await MainActor.run { viewer.needsYou = true; viewer.status = Engine.describeForUser(error) }
            Self.signal("TERM", match)
            try? await Task.sleep(for: .seconds(6))
            await cleanUp()
            throw error
        }
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Sends a signal to the job's CLI and its Claude Code child.
    static func signal(_ sig: String, _ match: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-\(sig)", "-f", match]
        try? p.run()
        p.waitUntilExit()
        let c = Process()
        c.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        c.arguments = ["-\(sig)", "-P", "\(childOf(match) ?? -1)"]
        if childOf(match) != nil { try? c.run(); c.waitUntilExit() }
    }

    static func childOf(_ match: String) -> Int32? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", match]
        let out = Pipe(); p.standardOutput = out
        try? p.run(); p.waitUntilExit()
        return Int32(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").first ?? "")
    }

    @MainActor static func togglePause(_ match: String, viewer: LiveViewer) {
        let paused = viewer.status.hasPrefix("Paused")
        signal(paused ? "CONT" : "STOP", match)
        viewer.status = paused ? "Resumed." : "Paused. Press Pause again to continue."
    }
}

extension WindowFinder {
    static func exists(_ id: CGWindowID) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] ?? []
        return !list.isEmpty
    }
}

extension Engine {
    nonisolated static func describeForUser(_ error: Error) -> String {
        switch error {
        case ClaudeJobError.failed(let m): return m
        case ClaudeJobError.noTable: return "Claude didn't return a table."
        case ClaudeJobError.notInstalled: return "Claude Code isn't installed."
        case let e as ScriptError: return e.message
        case AgentScreen.Failure.unavailable: return "This Mac couldn't create Sparehand's screen."
        default: return "\(error)"
        }
    }
}
