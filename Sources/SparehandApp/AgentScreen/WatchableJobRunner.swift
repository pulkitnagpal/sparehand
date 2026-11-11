import AppKit
import SparehandCore

/// Runs approved plans. Most run in the background and report progress on their card.
/// A research job runs on Sparehand's own screen so the user can watch: Notes opens there and the note is written
/// while Claude reads the pages. The user's own windows are never touched.
@MainActor
final class WatchableRun {
    let model: AppModel
    init(model: AppModel) { self.model = model }

    /// Steps worth watching.
    static let watched: Set<String> = ["research_to_note"]

    func say(_ s: String) { print("[watch] " + s) }

    func run(_ tap: Tap, progress: @escaping @MainActor (String) -> Void) async -> Tap? {
        guard tap.candidate.steps.contains(where: { Self.watched.contains($0.tool) }) else {
            return await model.engine.approve(tap.id) { line in Task { @MainActor in progress(line) } }
        }
        let screen = model.screen
        let viewer = LiveViewer(screen: screen)
        let scripts = OSAScriptRunner(timeout: 15)
        let notes = NotesWriter(runner: scripts)
        let bounds: CGRect
        do { bounds = try await screen.start() } catch {
            say("no agent screen: \(error); running in the background")
            return await model.engine.approve(tap.id) { line in Task { @MainActor in progress(line) } }
        }
        let area = screen.workArea()
        say("agent screen up at \(bounds)")
        viewer.setSteps(tap.candidate.steps.map { Self.describe($0) })
        viewer.status = "Opening Notes on Sparehand's screen…"
        let notesRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty
        let before = await notes.userWindowCount(notesRunning: notesRunning)
        let front = NSWorkspace.shared.frontmostApplication

        let result = await model.engine.approve(tap.id, progress: { line in
            Task { @MainActor in viewer.status = line; progress(line) }
        }, noteCreated: { noteID in
            await MainActor.run { self.say("note created") }
            guard let nw = try? await notes.show(noteID: noteID, ifNoUserWindows: before) else {
                await MainActor.run { self.say("Notes already has a window open: leaving the user's window alone") }
                return
            }
            try? await notes.setBounds(windowID: nw, area.insetBy(dx: 260, dy: 40))
            await MainActor.run { _ = front?.activate() }   // give focus back to what the user was doing
            try? await Task.sleep(for: .milliseconds(700))
            if let cg = await MainActor.run(body: { WindowFinder.windowID(owner: "Notes", title: nil, inside: bounds) }) {
                try? await viewer.start(windowIDs: [cg])
                await MainActor.run { self.say("streaming the Notes window") }
            }
        })
        viewer.finishSteps()
        viewer.finished = true
        viewer.needsYou = result?.state == .failed
        viewer.status = result?.note ?? "Done."
        if let ref = Tools.createdNoteID(tapID: tap.id, store: model.store) {
            viewer.onReveal = { Task { _ = try? await scripts.run("tell application \"Notes\"\nshow note id \(AppleScriptText.quoted(ref))\nactivate\nend tell") } }
        }
        await waitForClose(viewer)
        await viewer.stop()
        screen.stop()
        return result
    }

    /// Keeps the finished viewer up until Close, Show me, or a minute.
    func waitForClose(_ viewer: LiveViewer) async {
        var closed = false
        let reveal = viewer.onReveal
        viewer.onClose = { closed = true }
        viewer.onStop = { closed = true }
        viewer.onReveal = { reveal?(); closed = true }
        let until = Date().addingTimeInterval(60)
        while !closed && Date() < until { try? await Task.sleep(for: .milliseconds(200)) }
    }

    static func describe(_ s: ToolCall) -> String {
        switch s.tool {
        case "sort_by_content": "Sort into \((s.args["folders"]?.strings ?? []).prefix(3).joined(separator: ", "))…"
        case "organize_files": "Move files into monthly folders"
        case "move_to_bin": "Move files to the Bin"
        case "close_tabs": "Close \(s.args["urls"]?.strings.count ?? 0) tabs"
        case "stop_container": "Stop " + (s.args["names"]?.strings ?? []).joined(separator: ", ")
        case "quit_app": "Quit \(s.args["name"]?.string ?? "the app")"
        case "create_note": "Write the note “\(s.args["title"]?.string ?? "")”"
        case "research_to_note": "Read \(s.args["urls"]?.strings.count ?? 0) pages and write “\(s.args["title"]?.string ?? "a note")”"
        default: s.tool
        }
    }
}
