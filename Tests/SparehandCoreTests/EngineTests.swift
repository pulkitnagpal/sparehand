import Foundation
import Testing
@testable import SparehandCore

struct FixedWatcher: Watcher {
    let id: WatcherID
    let make: @Sendable (Environment) -> [Candidate]
    func candidates(_ env: Environment) async throws -> [Candidate] { make(env) }
}

struct FixedJudge: Judge {
    var show = true
    func verdict(for c: Candidate) async -> Verdict {
        Verdict(show: show, value: 3, title: "T \(c.id)", body: "B", actionLabel: "Do", source: .rules)
    }
}

final class Quiet: QuietRules, @unchecked Sendable {
    var quiet = false
    func isQuiet() -> Bool { quiet }
}

final class FakeJobs: JobRunner, @unchecked Sendable {
    var result: Result<String, Error> = .success("note-1")
    var ran: [String] = []
    func runTabsToNote(tap: Tap) async throws -> String { ran.append(tap.id); return try result.get() }
}

final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_794_000_000)
}

@Suite struct EngineTests {
    func candidate(_ id: String, _ watcher: WatcherID = .screenshots, plan: ActionPlan = .moveFiles([])) -> Candidate {
        Candidate(id: id, watcher: watcher, summary: "s", evidence: [], plan: plan, noticedAt: Date())
    }

    func engine(_ watchers: [any Watcher], judge: any Judge = FixedJudge(), quiet: Quiet = Quiet(), jobs: FakeJobs = FakeJobs(),
                clock: Clock = Clock(), store: Store? = nil, home: URL? = nil) throws -> Engine {
        let s = try store ?? Store.inMemory()
        let e = Environment(home: home ?? FileManager.default.temporaryDirectory, now: { clock.now }, store: s, scripts: RecordingRunner())
        return Engine(env: e, watchers: watchers, judge: judge, quiet: quiet, jobs: jobs, minGap: 600)
    }

    @Test func dedupsByFingerprint() async throws {
        let e = try engine([FixedWatcher(id: .screenshots) { _ in [candidate("a", plan: .moveFiles([]))] }])
        #expect(await e.tick().map(\.id) == ["a"])
        #expect(await e.tick().isEmpty)
        #expect(await e.feed().pending.map(\.id) == ["a"])
    }

    @Test func respectsMinGap() async throws {
        let clock = Clock()
        let w = FixedWatcher(id: .bin) { env in [self.candidate("x\(Int(env.now().timeIntervalSince1970))", .bin)] }
        let e = try engine([w], clock: clock)
        #expect(await e.tick().count == 1)
        clock.now += 300
        #expect(await e.tick().isEmpty)
        clock.now += 400
        #expect(await e.tick().count == 1)
    }

    @Test func quietHoldsTapsInFeed() async throws {
        let q = Quiet(); q.quiet = true
        let e = try engine([FixedWatcher(id: .screenshots) { _ in [candidate("a")] }], quiet: q)
        #expect(await e.tick().isEmpty)
        #expect(await e.feed().pending.map(\.id) == ["a"])
    }

    @Test func hiddenVerdictNotShown() async throws {
        let e = try engine([FixedWatcher(id: .screenshots) { _ in [candidate("a")] }], judge: FixedJudge(show: false))
        #expect(await e.tick().isEmpty)
        #expect(await e.feed().pending.isEmpty)
    }

    @Test func approveMovesFilesAndUndoRestores() async throws {
        let d = try TestDir()
        let from = try d.file("Desktop/a.png", "A")
        let plan = ActionPlan.moveFiles([FileMove(from: from, to: d.at("Pictures/Screenshots/2026-09/a.png"))])
        let e = try engine([FixedWatcher(id: .screenshots) { _ in [candidate("a", plan: plan)] }], home: d.url)
        _ = await e.tick()
        let done = await e.approve("a")
        #expect(done.state == .done)
        #expect(d.exists("Pictures/Screenshots/2026-09/a.png") && !d.exists("Desktop/a.png"))
        #expect(await e.feed().done.map(\.id) == ["a"])
        let undone = await e.undo("a")
        #expect(undone.state == .undone)
        #expect(d.read("Desktop/a.png") == "A")
    }

    @Test func deletePermanentlyRemovesItems() async throws {
        let d = try TestDir()
        let big = try d.file(".Trash/big.dmg")
        let e = try engine([FixedWatcher(id: .bin) { _ in [candidate("b", .bin, plan: .deletePermanently([big]))] }], home: d.url)
        _ = await e.tick()
        #expect(await e.approve("b").state == .done)
        #expect(!d.exists(".Trash/big.dmg"))
        #expect(await e.undo("b").state == .done)   // nothing to undo; state unchanged
    }

    @Test func dismissSnoozes() async throws {
        let clock = Clock()
        let e = try engine([FixedWatcher(id: .screenshots) { _ in [candidate("a")] }], clock: clock)
        _ = await e.tick()
        await e.dismiss("a", snooze: 3600)
        clock.now += 1800
        #expect(await e.tick().isEmpty)
        clock.now += 2400
        #expect(await e.tick().map(\.id) == ["a"])
    }

    @Test func tabsJobStoresNoteAndUndoDeletesIt() async throws {
        let jobs = FakeJobs()
        let runner = RecordingRunner()
        let s = try Store.inMemory()
        let env = Environment(home: FileManager.default.temporaryDirectory, now: { Date() }, store: s, scripts: runner)
        let w = FixedWatcher(id: .tabs) { _ in [self.candidate("t", .tabs, plan: .tabsToNote(topic: "Desks", tabs: []))] }
        let e = Engine(env: env, watchers: [w], judge: FixedJudge(), quiet: Quiet(), jobs: jobs)
        _ = await e.tick()
        let done = await e.approve("t")
        #expect(done.state == .done && done.resultRef == "note-1" && jobs.ran == ["t"])
        #expect(await e.undo("t").state == .undone)
        #expect(runner.scripts.last == "tell application \"Notes\" to delete note id \"note-1\"")
    }

    @Test func failedJobMarksFailed() async throws {
        let jobs = FakeJobs(); jobs.result = .failure(ClaudeJobError.noTable)
        let e = try engine([FixedWatcher(id: .tabs) { _ in [candidate("t", .tabs, plan: .tabsToNote(topic: "x", tabs: []))] }], jobs: jobs)
        _ = await e.tick()
        let t = await e.approve("t")
        #expect(t.state == .failed)
        #expect(t.note?.isEmpty == false)
    }
}
