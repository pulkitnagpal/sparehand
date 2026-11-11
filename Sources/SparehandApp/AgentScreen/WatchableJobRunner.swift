import AppKit
import SparehandCore

/// Runs an approved plan on Sparehand's own screen so the user can watch: a Finder window of the destination fills up
/// while files are sorted, and a created note opens there. The user's own windows are never touched.
/// When the job ends the viewer stays up with the result until the user closes it (or a minute passes).
@MainActor
final class WatchableRun {
    let model: AppModel
    init(model: AppModel) { self.model = model }

    static let fileTools: Set<String> = ["sort_by_content", "organize_files"]

    func say(_ s: String) { print("[watch] " + s) }

    func run(_ tap: Tap) async -> Tap? {
        let fileStep = tap.candidate.steps.first { Self.fileTools.contains($0.tool) }
        let noteStep = tap.candidate.steps.contains { $0.tool == "create_note" }
        guard fileStep != nil || noteStep else { say("no watchable step; running directly"); return await model.engine.approve(tap.id) }

        let screen = model.screen
        let viewer = LiveViewer(screen: screen)
        let scripts = OSAScriptRunner(timeout: 15)
        var finderWindow: String?
        var dest: URL?
        do {
            let bounds = try await screen.start()
            say("agent screen up at \(bounds)")
            let area = screen.workArea()
            viewer.setSteps(tap.candidate.steps.map { Self.describe($0) })
            viewer.status = "Starting on Sparehand's screen…"
            if let step = fileStep {
                let d = Tools.folderURL(step.args["into"]?.string ?? "~/Pictures/Screenshots", home: model.env.home)!
                dest = d
                try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
                do { finderWindow = try await scripts.run(Self.finderOpen(d, area)).trimmingCharacters(in: .whitespacesAndNewlines) }
                catch { say("Finder window failed: \(error)") }
                say("Finder window \(finderWindow ?? "none") for \(d.lastPathComponent)")
                var cg: CGWindowID?
                for _ in 0..<20 where cg == nil {
                    try await Task.sleep(for: .milliseconds(150))
                    cg = WindowFinder.windowID(owner: "Finder", title: d.lastPathComponent, inside: bounds)
                }
                say("Finder CG window: \(cg.map(String.init) ?? "not found")")
                if let cg { try await viewer.start(windowIDs: [cg]); say("viewer streaming") }
            }
            let started = Date()
            let result = await model.engine.approve(tap.id) { line in
                Task { @MainActor in
                    viewer.status = line
                    viewer.log.append(line)
                    if let i = line.range(of: " of ") { _ = i; viewer.advance(to: 0) }
                }
            }
            say(String(format: "plan finished in %.1fs: %@", Date().timeIntervalSince(started), result?.note ?? "-"))
            if noteStep, let bounds = screen.bounds {
                let notes = NotesWriter(runner: scripts)
                let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty
                let before = await notes.userWindowCount(notesRunning: running)
                if let ref = Tools.createdNoteID(tapID: tap.id, store: model.store),
                   let nw = try? await notes.show(noteID: ref, ifNoUserWindows: before) {
                    try? await notes.setBounds(windowID: nw, area.insetBy(dx: 200, dy: 60))
                    try await Task.sleep(for: .milliseconds(600))
                    if let cg = WindowFinder.windowID(owner: "Notes", title: nil, inside: bounds) {
                        if fileStep == nil { try await viewer.start(windowIDs: [cg]) } else { try? await viewer.add(windowID: cg) }
                    }
                }
            }
            viewer.finishSteps()
            viewer.finished = true
            viewer.needsYou = result?.state == .failed
            viewer.status = result?.note ?? "Done."
            await waitForClose(viewer, reveal: dest)
            if let w = finderWindow, !w.isEmpty { _ = try? await scripts.run("tell application \"Finder\" to close window id \(w)") }
            await viewer.stop()
            screen.stop()
            return result
        } catch {
            say("failed: \(error)")
            viewer.needsYou = true
            viewer.status = "\(error)"
            await viewer.stop()
            screen.stop()
            return await model.engine.tap(tap.id)
        }
    }

    /// Keeps the finished viewer up until Close, Show me, or a minute.
    func waitForClose(_ viewer: LiveViewer, reveal: URL?) async {
        var closed = false
        viewer.onClose = { closed = true }
        viewer.onStop = { closed = true }
        viewer.onReveal = {
            if let reveal { NSWorkspace.shared.open(reveal) }
            closed = true
        }
        let auto = CommandLine.arguments.contains("--approve-first") ? 8.0 : 60.0
        let until = Date().addingTimeInterval(auto)
        while !closed && Date() < until { try? await Task.sleep(for: .milliseconds(200)) }
    }

    static func describe(_ s: ToolCall) -> String {
        switch s.tool {
        case "sort_by_content": "Read each file and sort it into \((s.args["folders"]?.strings ?? []).prefix(4).joined(separator: ", "))…"
        case "organize_files": "Move files into monthly folders"
        case "move_to_bin": "Move files to the Bin"
        case "close_tabs": "Close \(s.args["urls"]?.strings.count ?? 0) tabs"
        case "stop_container": "Stop " + (s.args["names"]?.strings ?? []).joined(separator: ", ")
        case "quit_app": "Quit \(s.args["name"]?.string ?? "the app")"
        case "create_note": "Write the note “\(s.args["title"]?.string ?? "")”"
        default: s.tool
        }
    }

    static func finderOpen(_ dir: URL, _ rect: CGRect) -> String {
        """
        tell application "Finder"
          set w to make new Finder window to (POSIX file \(AppleScriptText.quoted(dir.path)) as alias)
          set current view of w to icon view
          set bounds of w to \(TerminalLauncher.bounds(rect.insetBy(dx: 160, dy: 40)))
          return id of w
        end tell
        """
    }
}
