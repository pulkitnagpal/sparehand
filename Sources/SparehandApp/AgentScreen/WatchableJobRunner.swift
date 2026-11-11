import AppKit
import SparehandCore

/// Runs an approved plan on Sparehand's own screen so the user can watch: a Finder window of the destination fills up
/// while files are sorted, and a created note opens there. The user's own windows are never touched.
@MainActor
final class WatchableRun {
    let model: AppModel
    init(model: AppModel) { self.model = model }

    static let fileTools: Set<String> = ["sort_by_content", "organize_files"]

    func run(_ tap: Tap) async -> Tap? {
        let fileStep = tap.candidate.steps.first { Self.fileTools.contains($0.tool) }
        let noteStep = tap.candidate.steps.contains { $0.tool == "create_note" }
        guard fileStep != nil || noteStep else { return await model.engine.approve(tap.id) }

        let screen = model.screen
        let viewer = LiveViewer(screen: screen)
        let scripts = OSAScriptRunner()
        var finderWindow: String?
        defer { }
        do {
            let bounds = try await screen.start()
            let area = screen.workArea()
            viewer.setSteps(tap.candidate.steps.map { Self.describe($0) } + ["Done"])
            viewer.status = "Starting on Sparehand's screen…"
            if let step = fileStep {
                let dest = Tools.folderURL(step.args["into"]?.string ?? "~/Pictures/Screenshots", home: model.env.home)!
                try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                finderWindow = try? await scripts.run(Self.finderOpen(dest, area)).trimmingCharacters(in: .whitespacesAndNewlines)
                try await Task.sleep(for: .milliseconds(700))
                if let id = WindowFinder.windowID(owner: "Finder", title: dest.lastPathComponent, inside: bounds) {
                    try await viewer.start(windowIDs: [id])
                }
            }
            let result = await model.engine.approve(tap.id) { line in
                Task { @MainActor in viewer.status = line }
            }
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
            viewer.status = result?.note ?? "Done."
            try await Task.sleep(for: .seconds(4))
            if let w = finderWindow, !w.isEmpty { _ = try? await scripts.run("tell application \"Finder\" to close window id \(w)") }
            await viewer.stop()
            screen.stop()
            return result
        } catch {
            viewer.needsYou = true
            viewer.status = "\(error)"
            await viewer.stop()
            screen.stop()
            return await model.engine.tap(tap.id)
        }
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
