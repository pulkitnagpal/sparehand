import Foundation
import Testing
@testable import SparehandCore

struct NoScripts: ScriptRunner {
    func run(_ source: String) async throws -> String { "" }
}

func env(_ d: TestDir, now: Date = Date(timeIntervalSince1970: 1_794_000_000), store: Store? = nil, scripts: ScriptRunner = NoScripts()) throws -> Environment {
    Environment(home: d.url, now: { now }, store: try store ?? Store.inMemory(), scripts: scripts)
}

@Suite struct ScreenshotsWatcherTests {
    let now = Date(timeIntervalSince1970: 1_794_000_000) // 2026-11-07
    let old = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21

    func shots(_ d: TestDir, _ names: [String], created: Date) throws {
        for n in names { try d.file("Desktop/\(n)", created: created) }
    }

    @Test func belowThresholdNoCandidate() async throws {
        let d = try TestDir()
        try shots(d, (1...4).map { "Screenshot 2026-09-0\($0) at 10.00.00.png" }, created: old)
        #expect(try await ScreenshotsWatcher(minCount: 5).candidates(env(d, now: now)).isEmpty)
    }

    @Test func groupsByMonthFromName() async throws {
        let d = try TestDir()
        try shots(d, ["Screenshot 2026-09-01 at 10.00.00.png", "Screenshot 2026-09-02 at 11.30.12.png",
                      "Screen Recording 2026-08-15 at 09.01.02.mov"], created: old)
        let c = try #require(try await ScreenshotsWatcher(minCount: 3).candidates(env(d, now: now)).first)
        guard case .moveFiles(let moves) = c.plan else { Issue.record("plan"); return }
        let byName = Dictionary(uniqueKeysWithValues: moves.map { ($0.from.lastPathComponent, $0.to) })
        #expect(byName["Screenshot 2026-09-02 at 11.30.12.png"] == d.at("Pictures/Screenshots/2026-09/Screenshot 2026-09-02 at 11.30.12.png"))
        #expect(byName["Screen Recording 2026-08-15 at 09.01.02.mov"]?.deletingLastPathComponent().lastPathComponent == "2026-08")
        #expect(c.facts["count"] == "3")
        #expect(c.facts["oldestMonth"] == "August 2026")
        #expect(c.evidence.first == EvidenceItem(label: "September 2026", detail: "2 files"))
        #expect(c.watcher == .screenshots)
    }

    @Test func keepsRecent() async throws {
        let d = try TestDir()
        try shots(d, (1...3).map { "Screenshot 2026-09-0\($0) at 10.00.00.png" }, created: old)
        try shots(d, ["Screenshot 2026-11-06 at 10.00.00.png"], created: now.addingTimeInterval(-3600))
        let c = try #require(try await ScreenshotsWatcher(minCount: 3, keepRecentDays: 2).candidates(env(d, now: now)).first)
        guard case .moveFiles(let moves) = c.plan else { Issue.record("plan"); return }
        #expect(moves.count == 3)
        #expect(c.facts["kept"] == "1")
        #expect(c.summary == "3 screenshots are on the Desktop, oldest from September 2026; 1 recent one would stay.")
    }

    @Test func ignoresNonScreenshots() async throws {
        let d = try TestDir()
        try shots(d, ["Screenshot notes.txt", "IMG_1.png", "Screenshot 2026-09-01 at 10.00.00.pdf",
                      "Screenshot 2026-09-01 at 10.00.00.png"], created: old)
        #expect(try await ScreenshotsWatcher(minCount: 2).candidates(env(d, now: now)).isEmpty)
    }

    @Test func fingerprintStableAcrossRuns() async throws {
        let d = try TestDir()
        try shots(d, (1...3).map { "Screenshot 2026-09-0\($0) at 10.00.00.png" }, created: old)
        let w = ScreenshotsWatcher(minCount: 3)
        let a = try await w.candidates(env(d, now: now)).first?.id
        let b = try await w.candidates(env(d, now: now.addingTimeInterval(60))).first?.id
        #expect(a != nil && a == b)
    }
}
