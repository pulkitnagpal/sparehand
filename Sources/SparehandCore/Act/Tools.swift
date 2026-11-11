import AppKit
import Foundation

/// One step of a plan: a tool name and the arguments a model chose.
public struct ToolCall: Codable, Sendable, Equatable {
    public var tool: String
    public var args: JSONValue
    public init(tool: String, args: JSONValue) { self.tool = tool; self.args = args }
}

public struct ToolSpec: Sendable {
    public var name: String
    public var prompt: String
    public var reversible: Bool
}

/// Files picked by description, so a model can say "the screenshots on the Desktop" without listing 281 names.
public struct FileSelector: Sendable, Equatable {
    public var folder: String
    public var kinds: [String] = []
    public var nameContains: String?
    public var olderThanDays: Double?
    public var names: [String] = []

    public init(folder: String, kinds: [String] = [], nameContains: String? = nil, olderThanDays: Double? = nil, names: [String] = []) {
        self.folder = folder; self.kinds = kinds; self.nameContains = nameContains; self.olderThanDays = olderThanDays; self.names = names
    }

    public init?(_ v: JSONValue?) {
        guard let v, let folder = v["folder"]?.string else { return nil }
        self.folder = folder
        kinds = (v["kinds"]?.strings ?? []).map { $0.hasPrefix(".") ? String($0.dropFirst()).lowercased() : $0.lowercased() }
        nameContains = v["name_contains"]?.string
        olderThanDays = v["older_than_days"]?.number
        names = v["names"]?.strings ?? []
    }

    /// Top-level files only, inside the home folder only.
    public func resolve(home: URL, now: Date) -> [URL] {
        guard let dir = Tools.folderURL(folder, home: home) else { return [] }
        let normalize = { (s: String) in s.replacingOccurrences(of: "\u{202F}", with: " ").lowercased() }
        let wanted = Set(names.map(normalize))
        return Senses.list(dir).filter { u in
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            if v?.isDirectory == true { return false }
            let name = normalize(u.lastPathComponent)
            if !wanted.isEmpty && !wanted.contains(name) { return false }
            if !kinds.isEmpty && !kinds.contains(u.pathExtension.lowercased()) { return false }
            if let n = nameContains, !n.isEmpty, !name.contains(normalize(n)) { return false }
            if let days = olderThanDays, let d = v?.contentModificationDate, now.timeIntervalSince(d) < days * 86_400 { return false }
            return true
        }
    }
}

public struct ToolContext: Sendable {
    public var env: Environment
    public var local: LocalModel?
    public var progress: @Sendable (String) -> Void
    public init(env: Environment, local: LocalModel?, progress: @escaping @Sendable (String) -> Void = { _ in }) {
        self.env = env; self.local = local; self.progress = progress
    }
}

public enum ToolError: Error, Equatable {
    case unknownTool(String), badArgs(String), nothingToDo(String), failed(String)
    public var message: String {
        switch self {
        case .unknownTool(let t): "Sparehand has no tool called \(t)."
        case .badArgs(let m), .nothingToDo(let m), .failed(let m): m
        }
    }
}

/// What to do to reverse a step, kept per tap.
struct UndoRecord: Codable {
    var kind: String          // moves | reopen_tabs | start_containers | reopen_app | delete_note
    var values: [String] = []
    var extra: String?
}

public enum Tools {
    public static let all: [ToolSpec] = [
        ToolSpec(name: "sort_by_content", prompt: #"sort_by_content(files: <selector>, into: "~/Pictures/<Name>", folders: ["3-7 short folder names chosen from what these files show"]): Sparehand reads each file's content on this Mac and moves it into the best of those folders (anything that fits none goes to "Other"). Reversible."#, reversible: true),
        ToolSpec(name: "organize_files", prompt: #"organize_files(files: <selector>, into: "~/<path>", by: "month"): move files into one subfolder per month. Reversible."#, reversible: true),
        ToolSpec(name: "move_to_bin", prompt: #"move_to_bin(files: <selector>): move files to the Bin. Reversible."#, reversible: true),
        ToolSpec(name: "quit_app", prompt: #"quit_app(name: "<running app>"): quit an app; it can be reopened. Reversible."#, reversible: true),
        ToolSpec(name: "stop_container", prompt: #"stop_container(names: ["<container>"]): stop Docker containers; they can be started again. Reversible."#, reversible: true),
        ToolSpec(name: "close_tabs", prompt: #"close_tabs(urls: ["<url exactly as in the snapshot>"]): close browser tabs; they can be reopened. Reversible."#, reversible: true),
        ToolSpec(name: "create_note", prompt: #"create_note(title: "<title>", html: "<simple HTML: h2, p, ul, li, b, a>"): create a note in Apple Notes. Reversible."#, reversible: true),
        ToolSpec(name: "show_report", prompt: #"show_report(text: "<=60 words"): tell the user something useful; changes nothing."#, reversible: true),
    ]

    public static func spec(_ name: String) -> ToolSpec? { all.first { $0.name == name } }

    public static var catalogue: String {
        """
        A <selector> picks files: {"folder": "Desktop"|"Downloads", "kinds": [".png"], "name_contains": "text", "older_than_days": 7, "names": ["exact file name"]}. Only "folder" is required.
        A plan has 1-5 steps, each {"tool": "<name>", "args": {...}}. Tools:
        """ + "\n" + all.map { "- " + $0.prompt }.joined(separator: "\n")
    }

    /// "Desktop", "~/Pictures/X" or "Pictures/X" inside the home folder; nil if it points outside.
    public static func folderURL(_ s: String, home: URL) -> URL? {
        var rel = s.trimmingCharacters(in: .whitespaces)
        if rel.hasPrefix("~/") { rel.removeFirst(2) } else if rel == "~" { rel = "" }
        if rel.hasPrefix("/") {
            guard rel.hasPrefix(home.path) else { return nil }
            rel = String(rel.dropFirst(home.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        guard !rel.split(separator: "/").contains("..") else { return nil }
        return rel.isEmpty ? home : home.appendingPathComponent(rel, isDirectory: true)
    }

    // MARK: - running

    /// Runs one step. Returns a short line for the feed.
    public static func run(_ call: ToolCall, tapID: String, ctx: ToolContext) async throws -> String {
        let env = ctx.env, a = call.args
        switch call.tool {
        case "sort_by_content":
            guard let sel = FileSelector(a["files"]), let into = folderURL(a["into"]?.string ?? "~/Pictures/Screenshots", home: env.home) else { throw ToolError.badArgs("Which files, and where to?") }
            let folders = a["folders"]?.strings.filter { !$0.isEmpty }.prefix(8).map { $0 } ?? []
            guard !folders.isEmpty else { throw ToolError.badArgs("No folders to sort into.") }
            guard let local = ctx.local else { throw ToolError.failed("The local model isn't running.") }
            let files = sel.resolve(home: env.home, now: env.now())
            guard !files.isEmpty else { throw ToolError.nothingToDo("Those files are no longer there.") }
            var counts: [String: Int] = [:]
            let mover = FileMover(store: env.store)
            for (i, f) in files.enumerated() {
                let text = Senses.ocr([f])[f] ?? ""
                let folder = (try? await local.classify(text: text, into: folders + ["Other"])) ?? "Other"
                _ = try mover.perform([FileMove(from: f, to: into.appendingPathComponent(folder).appendingPathComponent(f.lastPathComponent))], tapID: tapID)
                counts[folder, default: 0] += 1
                ctx.progress("\(i + 1) of \(files.count) → \(folder)")
            }
            try addUndo(UndoRecord(kind: "moves"), tapID: tapID, store: env.store)
            return "Sorted \(files.count) into \(counts.count) folders"

        case "organize_files":
            guard let sel = FileSelector(a["files"]), let into = folderURL(a["into"]?.string ?? "~/Pictures/Screenshots", home: env.home) else { throw ToolError.badArgs("Which files, and where to?") }
            let files = sel.resolve(home: env.home, now: env.now())
            guard !files.isEmpty else { throw ToolError.nothingToDo("Those files are no longer there.") }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM"
            let moves = files.map { u -> FileMove in
                let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? env.now()
                return FileMove(from: u, to: into.appendingPathComponent(f.string(from: d)).appendingPathComponent(u.lastPathComponent))
            }
            let r = try FileMover(store: env.store).perform(moves, tapID: tapID)
            try addUndo(UndoRecord(kind: "moves"), tapID: tapID, store: env.store)
            return "Moved \(r.moved.count) into monthly folders"

        case "move_to_bin":
            guard let sel = FileSelector(a["files"]) else { throw ToolError.badArgs("Which files?") }
            let files = sel.resolve(home: env.home, now: env.now())
            guard !files.isEmpty else { throw ToolError.nothingToDo("Those files are no longer there.") }
            var n = 0
            for u in files {
                var result: NSURL?
                do { try FileManager.default.trashItem(at: u, resultingItemURL: &result) } catch { continue }
                if let r = result as URL? { try env.store.appendJournal(JournalEntry(tapID: tapID, move: FileMove(from: u, to: r), at: env.now())); n += 1 }
            }
            try addUndo(UndoRecord(kind: "moves"), tapID: tapID, store: env.store)
            return "Moved \(n) to the Bin"

        case "quit_app":
            guard let name = a["name"]?.string,
                  let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else { throw ToolError.nothingToDo("That app isn't running.") }
            let bundle = app.bundleURL?.path
            guard app.terminate() else { throw ToolError.failed("\(name) didn't quit.") }
            try addUndo(UndoRecord(kind: "reopen_app", values: bundle.map { [$0] } ?? []), tapID: tapID, store: env.store)
            return "Quit \(name)"

        case "stop_container":
            let names = a["names"]?.strings ?? []
            guard !names.isEmpty, let docker = Shell.which("docker") else { throw ToolError.nothingToDo("No containers to stop.") }
            _ = Shell.run(docker, ["stop"] + names, timeout: 60)
            try addUndo(UndoRecord(kind: "start_containers", values: names), tapID: tapID, store: env.store)
            return "Stopped " + names.joined(separator: ", ")

        case "close_tabs":
            let wanted = Set((a["urls"]?.strings ?? []).map(Redactor.url))
            let tabs = await BrowserTabs.all(runner: env.scripts, running: env.runningApps()).filter { wanted.contains(Redactor.url($0.url.absoluteString)) }
            guard !tabs.isEmpty else { throw ToolError.nothingToDo("Those tabs are already closed.") }
            for (browser, group) in Dictionary(grouping: tabs, by: \.browser) {
                _ = try await env.scripts.run(BrowserTabs.closeScript(app: browser, urls: group.map(\.url.absoluteString)))
                try addUndo(UndoRecord(kind: "reopen_tabs", values: group.map(\.url.absoluteString), extra: browser), tapID: tapID, store: env.store)
            }
            return "Closed \(tabs.count) tabs"

        case "create_note":
            let title = a["title"]?.string ?? "Sparehand note"
            let html = ClaudeJob.sanitize(a["html"]?.string ?? "")
            let id = try await NotesWriter(runner: env.scripts).create(title: title, html: html)
            try addUndo(UndoRecord(kind: "delete_note", values: [id]), tapID: tapID, store: env.store)
            return "Created the note “\(title)”"

        case "show_report":
            return a["text"]?.string ?? ""

        default:
            throw ToolError.unknownTool(call.tool)
        }
    }

    /// Reverses everything a tap did, newest first.
    public static func undo(tapID: String, env: Environment) async throws -> String {
        var notes: [String] = []
        for r in undoRecords(tapID: tapID, store: env.store).reversed() {
            switch r.kind {
            case "moves":
                let rep = try FileMover(store: env.store).undo(tapID: tapID)
                if !rep.moved.isEmpty { notes.append("Put \(rep.moved.count) files back") }
            case "reopen_tabs":
                let urls = r.values.compactMap(URL.init(string:))
                if let app = r.extra, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: BrowserTabs.bundleID(app) ?? "") {
                    try await NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
                }
                notes.append("Reopened \(urls.count) tabs")
            case "start_containers":
                if let docker = Shell.which("docker") { _ = Shell.run(docker, ["start"] + r.values, timeout: 60) }
                notes.append("Started " + r.values.joined(separator: ", "))
            case "reopen_app":
                if let p = r.values.first { try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: p), configuration: NSWorkspace.OpenConfiguration()) }
                notes.append("Reopened the app")
            case "delete_note":
                if let id = r.values.first { try await NotesWriter(runner: env.scripts).delete(noteID: id) }
                notes.append("Deleted the note")
            default: break
            }
        }
        try env.store.setSetting("undo.\(tapID)", "[]")
        return notes.joined(separator: " · ")
    }

    /// The note a tap created, if any.
    public static func createdNoteID(tapID: String, store: Store) -> String? {
        undoRecords(tapID: tapID, store: store).first { $0.kind == "delete_note" }?.values.first
    }

    static func undoRecords(tapID: String, store: Store) -> [UndoRecord] {
        guard let s = try? store.setting("undo.\(tapID)") else { return [] }
        return (try? JSONDecoder().decode([UndoRecord].self, from: Data(s.utf8))) ?? []
    }

    static func addUndo(_ r: UndoRecord, tapID: String, store: Store) throws {
        var list = undoRecords(tapID: tapID, store: store)
        if r.kind == "moves", list.contains(where: { $0.kind == "moves" }) { return }
        list.append(r)
        try store.setSetting("undo.\(tapID)", String(decoding: try JSONEncoder().encode(list), as: UTF8.self))
    }
}
