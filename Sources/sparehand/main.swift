import Foundation
import SparehandCore

// sparehand: the command-line side of Sparehand (debugging, demo seeding, and the watchable Claude Code runner).
setvbuf(stdout, nil, _IONBF, 0)

let usage = """
    usage:
      sparehand scan                       show what the watchers notice and what the judge says (no actions)
      sparehand judge --sample <watcher>   ask the judge about a sample (screenshots | bin | tabs)
      sparehand claude-run --job <tapID>   run the tabs → note job with Claude Code, printing its progress
      sparehand undo <tapID>               undo a done suggestion
      sparehand terminal-test              open a Terminal window Sparehand owns, then close it
      sparehand note-test                  create and delete a test note in Notes
      sparehand demo-seed [options]        fill a Demo account with screenshots, Bin items and tabs
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func openStore() -> Store {
    do { return try Store(path: Environment.supportDirectory.appendingPathComponent("sparehand.sqlite")) }
    catch { fail("can't open the store: \(error)") }
}

func value(after flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let watchers: [any Watcher] = [ScreenshotsWatcher(), BinWatcher(), TabsWatcher()]
let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "scan":
    let env = Environment.live(store: openStore())
    let judge = FallbackJudge(primary: LocalModelJudge())
    for w in watchers {
        let found = (try? await w.candidates(env)) ?? []
        print("[\(w.id.rawValue)] \(found.isEmpty ? "nothing" : "\(found.count) candidate(s)")")
        for c in found {
            let v = await judge.verdict(for: c)
            print("  \(c.summary)")
            print("  → \(v.show ? "show" : "stay quiet") (\(v.source.rawValue)): \(v.title) · \(v.body) [\(v.actionLabel)]")
        }
    }

case "judge":
    let samples: [String: Candidate] = [
        "screenshots": Candidate(id: "sample-s", watcher: .screenshots, summary: "120 screenshots are on the Desktop, oldest from June 2026; 3 recent ones would stay.",
                                 facts: ["count": "120", "kept": "3", "oldestMonth": "June 2026"], evidence: [], plan: .moveFiles([]), noticedAt: Date()),
        "bin": Candidate(id: "sample-b", watcher: .bin, summary: "The Bin holds 12.4 GB; the 3 largest items are 11.3 GB.",
                         facts: ["totalGB": "12.4 GB", "itemsGB": "11.3 GB", "n": "3"], evidence: [], plan: .deletePermanently([]), noticedAt: Date()),
        "tabs": Candidate(id: "sample-t", watcher: .tabs, summary: "7 open tabs about Standing Desks, open since Monday.",
                          facts: ["count": "7", "topic": "Standing Desks", "since": "Monday"], evidence: [], plan: .tabsToNote(topic: "Standing Desks", tabs: []), noticedAt: Date()),
    ]
    guard let name = value(after: "--sample", in: args), let c = samples[name] else { fail(usage) }
    let start = Date()
    let v = await FallbackJudge(primary: LocalModelJudge()).verdict(for: c)
    print("\(v.show ? "show" : "stay quiet") (\(v.source.rawValue), \(String(format: "%.1f", Date().timeIntervalSince(start))) s): \(v.title) · \(v.body) [\(v.actionLabel)]")

case "claude-run":
    guard let id = value(after: "--job", in: args) else { fail(usage) }
    let store = openStore()
    guard let tap = try? store.tap(id: id), case .tabsToNote(let topic, let tabs) = tap.candidate.plan else { fail("no tabs job \(id)") }
    let jobs = Environment.supportDirectory.appendingPathComponent("jobs", isDirectory: true)
    try? FileManager.default.createDirectory(at: jobs, withIntermediateDirectories: true)
    let errorFile = jobs.appendingPathComponent("\(id).error")
    try? FileManager.default.removeItem(at: errorFile)
    func giveUp(_ message: String) -> Never {
        print("\n\(message)")
        try? message.write(to: errorFile, atomically: true, encoding: .utf8)
        exit(1)
    }
    guard let claude = ClaudeJob.locate() else { giveUp("Claude Code isn't installed.") }

    print("Sparehand → Claude Code\n")
    print("Comparing \(tabs.count) pages about \(topic):")
    for t in tabs { print("  • \(t.title)") }
    print("")
    let p = Process()
    p.executableURL = claude
    p.arguments = ClaudeJob.arguments(prompt: ClaudeJob.prompt(topic: topic, tabs: tabs))
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { giveUp("Couldn't start Claude Code: \(error)") }
    var lines: [String] = []
    var buffer = Data()
    let handle = out.fileHandleForReading
    while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[..<nl], as: UTF8.self)
            buffer.removeSubrange(...nl)
            lines.append(line)
            if let shown = ClaudeJob.progressLine(line) { print("  \(shown)") }
        }
    }
    p.waitUntilExit()
    do {
        let table = ClaudeJob.sanitize(try ClaudeJob.extractTable(try ClaudeJob.finalText(lines)))
        try table.write(to: jobs.appendingPathComponent("\(id).html"), atomically: true, encoding: .utf8)
        print("\nTable saved. Putting it in Notes…")
    } catch ClaudeJobError.noTable {
        giveUp("Claude didn't return a table.")
    } catch ClaudeJobError.failed(let m) {
        giveUp("Claude stopped: \(m)")
    } catch {
        giveUp("\(error)")
    }

case "undo":
    guard args.count > 1 else { fail(usage) }
    let env = Environment.live(store: openStore())
    struct NoJobs: JobRunner { func runTabsToNote(tap: Tap) async throws -> String { throw ClaudeJobError.notInstalled } }
    struct NeverQuiet: QuietRules { func isQuiet() -> Bool { false } }
    let engine = Engine(env: env, watchers: [], judge: RuleJudge(), quiet: NeverQuiet(), jobs: NoJobs())
    let t = await engine.undo(args[1])
    print("\(t.id): \(t.state.rawValue)\(t.note.map { " (\($0))" } ?? "")")

case "terminal-test":
    let term = TerminalLauncher(runner: OSAScriptRunner())
    do {
        let id = try await term.open(command: "echo 'Sparehand opened this window and will close it in 3 seconds.'", title: "Sparehand test")
        print("opened Terminal window \(id)")
        try await Task.sleep(for: .seconds(3))
        try await term.close(windowID: id)
        print("closed it")
    } catch { fail("terminal-test failed: \(error)") }

case "note-test":
    let notes = NotesWriter(runner: OSAScriptRunner())
    do {
        let id = try await notes.create(title: "Sparehand test note", html: "<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>")
        print("created note \(id)")
        try await Task.sleep(for: .seconds(2))
        try await notes.delete(noteID: id)
        print("deleted it")
    } catch { fail("note-test failed: \(error)") }

case "demo-seed":
    await DemoSeed.run(args: Array(args.dropFirst()))

default:
    print(usage)
}
