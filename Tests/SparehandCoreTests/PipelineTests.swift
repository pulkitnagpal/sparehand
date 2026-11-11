import Foundation
import Testing
@testable import SparehandCore

struct FakeClaude: ClaudeBackend {
    var label: String { "fake" }
    let answer: String
    let calls: Counter
    func complete(system: String, user: String) async throws -> ClaudeReply {
        calls.bump()
        return ClaudeReply(text: answer, costUSD: 0.01)
    }
}

final class Counter: @unchecked Sendable {
    private var n = 0
    private let lock = NSLock()
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

func testEnv(_ dir: TestDir) throws -> Environment {
    var e = Environment(home: dir.url, now: { Date() }, store: try Store.inMemory(), scripts: FailingRunner(code: -1743))
    e.runningApps = { ["Finder", "Notes"] }
    return e
}

let sortAnswer = """
    Here you go: {"propose": true, "steps": [{"tool": "sort_by_content", "args": {"files": {"folder": "Desktop", "kinds": [".png"]},
    "into": "~/Pictures/Screenshots", "folders": ["Travel", "Receipts"]}}], "card_title": "Sort 6 screenshots",
    "card_body": "Read each screenshot and move it into Travel or Receipts in Pictures.", "why_noticed": "6 screenshots on the Desktop",
    "action_label": "Sort them", "repeat_title": "Sort {count} new screenshots", "confidence": 4}
    """

@Suite struct RedactorTests {
    @Test func stripsSecrets() {
        #expect(!Redactor.text("export OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwx").contains("sk-abc"))
        #expect(!Redactor.text("curl -H 'Authorization: Bearer abcdefghijklmnop123'").contains("abcdefghijklmnop123"))
        #expect(Redactor.text("ghp_abcdefghijklmnopqrstuvwxyz0123") == "[REDACTED]")
        #expect(Redactor.text("git clone https://user:hunter2@github.com/x").contains("[REDACTED]@github.com"))
    }

    @Test func keepsOrdinaryText() {
        #expect(Redactor.text("npm run build in ~/code/app") == "npm run build in ~/code/app")
        #expect(Redactor.url("https://9to5mac.com/2026/11/10/apple-announces-a-long-slug/?utm=abc#top") == "https://9to5mac.com/2026/11/10/apple-announces-a-long-slug/")
    }
}

@Suite struct SelectorTests {
    @Test func picksTopLevelFilesByKindAndName() throws {
        let d = try TestDir()
        try d.file("Desktop/Screenshot 2026-01-01 at 9.00.00\u{202F}AM.png")
        try d.file("Desktop/notes.txt")
        try d.file("Desktop/sub/Screenshot inner.png")
        let sel = FileSelector(folder: "Desktop", kinds: ["png"], nameContains: "screenshot")
        #expect(sel.resolve(home: d.url, now: Date()).map(\.lastPathComponent) == ["Screenshot 2026-01-01 at 9.00.00\u{202F}AM.png"])
        // Models often write a normal space where macOS uses a narrow one.
        let byName = FileSelector(folder: "Desktop", names: ["Screenshot 2026-01-01 at 9.00.00 AM.png"])
        #expect(byName.resolve(home: d.url, now: Date()).count == 1)
    }

    @Test func refusesPathsOutsideHome() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(Tools.folderURL("~/../y", home: home) == nil)
        #expect(Tools.folderURL("/etc", home: home) == nil)
        #expect(Tools.folderURL("~/Pictures/Screenshots", home: home)?.path == "/Users/x/Pictures/Screenshots")
    }
}

@Suite struct GateTests {
    @Test func parsesAProposalFromProse() throws {
        let p = try #require(Gate.parse(sortAnswer))
        #expect(p.steps.map(\.tool) == ["sort_by_content"])
        #expect(p.confidence == 4)
        #expect(p.repeatTitle == "Sort {count} new screenshots")
    }

    @Test func silenceIsNil() {
        #expect(Gate.parse(#"{"propose": false, "steps": []}"#) == nil)
        #expect(Gate.parse("not json") == nil)
    }

    @Test func promptListsEveryToolAndTheMemory() {
        let s = Gate.system(memory: ["keeps screenshots on purpose"])
        for t in Tools.all { #expect(s.contains(t.name)) }
        #expect(s.contains("keeps screenshots on purpose"))
    }
}

@Suite struct ValidatorTests {
    func snap() -> Snapshot { Snapshot(takenAt: Date(), json: Data("{}".utf8), containers: ["pg-old"], runningApps: ["Notes"]) }

    @Test func acceptsGroundedPlan() throws {
        let d = try TestDir()
        for i in 0..<3 { try d.file("Desktop/shot\(i).png") }
        let env = try testEnv(d)
        let p = try #require(Gate.parse(sortAnswer))
        guard case .success(let c) = Validator.check(p, snapshot: snap(), env: env) else { Issue.record("rejected"); return }
        #expect(c.targets.count == 3)
    }

    @Test func rejectsInventedTargetsAndScaryCopy() throws {
        let d = try TestDir()
        let env = try testEnv(d)
        let p = try #require(Gate.parse(sortAnswer))
        // No files match.
        if case .success = Validator.check(p, snapshot: snap(), env: env) { Issue.record("accepted an empty selector") }
        // A container that isn't running.
        let stop = Proposal(steps: [ToolCall(tool: "stop_container", args: .object(["names": .array([.string("ghost")])]))],
                            title: "Stop it", body: "Stop the container.", why: "", actionLabel: "Stop", repeatTitle: nil, confidence: 5)
        if case .success = Validator.check(stop, snapshot: snap(), env: env) { Issue.record("accepted a ghost container") }
        // Copy that says delete when the plan only moves.
        try d.file("Desktop/a.png")
        var scary = p; scary.body = "This will delete your screenshots."
        if case .success = Validator.check(scary, snapshot: snap(), env: env) { Issue.record("accepted contradicting copy") }
        // Low confidence.
        var unsure = p; unsure.confidence = 2
        if case .success = Validator.check(unsure, snapshot: snap(), env: env) { Issue.record("accepted confidence 2") }
    }
}

@Suite struct EngineTests {
    @Test func claudeOfferThenLearnedSkillRunsWithoutClaude() async throws {
        let d = try TestDir()
        for i in 0..<6 { try d.file("Desktop/Screenshot \(i).png") }
        let env = try testEnv(d)
        let calls = Counter()
        let engine = Engine(env: env, senses: Senses(env: env), local: nil, claude: FakeClaude(answer: sortAnswer, calls: calls), quiet: NeverQuiet())

        let first = await engine.look(force: true)
        let tap = try #require(first.taps.first)
        #expect(tap.candidate.origin == .claude)
        #expect(calls.value == 1)

        // Approve: with no local model the sort step fails cleanly, and nothing moves.
        let failed = try #require(await engine.approve(tap.id))
        #expect(failed.state == .failed)
        #expect(d.exists("Desktop/Screenshot 0.png"))

        // Simulate the approved run with a month organiser instead, which needs no model, so a skill is learned.
        var t2 = tap
        t2.id = "organise"; t2.candidate.id = "organise"
        t2.candidate.steps = [ToolCall(tool: "organize_files", args: .object(["files": .object(["folder": .string("Desktop"), "kinds": .array([.string(".png")])]),
                                                                              "into": .string("~/Pictures/Screenshots"), "by": .string("month")]))]
        try env.store.upsert(t2)
        let done = try #require(await engine.approve("organise"))
        #expect(done.state == .done)
        #expect(!d.exists("Desktop/Screenshot 0.png"))
        #expect(Skills.all(env.store).count == 1)

        // New screenshots: the skill offers on this Mac, Claude isn't asked.
        for i in 10..<16 { try d.file("Desktop/Screenshot \(i).png") }
        let second = await engine.look(force: true)
        let local = try #require(second.taps.first)
        #expect(local.candidate.origin == .skill)
        #expect(calls.value == 1)

        // Undo puts the first batch back.
        let undone = try #require(await engine.undo("organise"))
        #expect(undone.state == .undone)
        #expect(d.exists("Desktop/Screenshot 0.png"))
    }

    @Test func neverGoesIntoMemoryAndIsNotOfferedAgain() async throws {
        let d = try TestDir()
        for i in 0..<6 { try d.file("Desktop/Screenshot \(i).png") }
        let env = try testEnv(d)
        let calls = Counter()
        let engine = Engine(env: env, senses: Senses(env: env), local: nil, claude: FakeClaude(answer: sortAnswer, calls: calls), quiet: NeverQuiet())
        let tap = try #require(await engine.look(force: true).taps.first)
        await engine.never(tap.id)
        #expect(await engine.memory().first?.contains("Sort 6 screenshots") == true)
        let again = await engine.look(force: true)
        #expect(again.taps.isEmpty)
        #expect(again.steps.contains("already offered"))
    }

    @Test func noClaudeMeansOnlySkills() async throws {
        let d = try TestDir()
        let env = try testEnv(d)
        let engine = Engine(env: env, senses: Senses(env: env), local: nil, claude: nil, quiet: NeverQuiet())
        let r = await engine.look(force: true)
        #expect(r.taps.isEmpty)
        #expect(r.steps.last == "no Claude connected: only learned skills run")
    }
}
