import Foundation
import Testing
@testable import SparehandCore

func sampleTap(id: String = "t1", watcher: WatcherID = .screenshots, state: TapState = .pending, at: TimeInterval = 1_800_000_000) -> Tap {
    let c = Candidate(id: id, watcher: watcher, summary: "s", evidence: [], plan: .moveFiles([]), noticedAt: Date(timeIntervalSince1970: at))
    let v = Verdict(show: true, value: 3, title: "T", body: "B", actionLabel: "Do", source: .rules)
    return Tap(candidate: c, verdict: v, state: state, createdAt: Date(timeIntervalSince1970: at))
}

@Suite struct StoreTests {
    @Test func tapRoundTrip() throws {
        let s = try Store.inMemory()
        var t = sampleTap()
        try s.upsert(t)
        #expect(try s.tap(id: "t1") == t)
        t.state = .done; t.resultRef = "note-1"
        try s.upsert(t)
        #expect(try s.tap(id: "t1")?.state == .done)
        #expect(try s.tap(id: "nope") == nil)
    }

    @Test func filtersByState() throws {
        let s = try Store.inMemory()
        try s.upsert(sampleTap(id: "a", state: .pending, at: 100))
        try s.upsert(sampleTap(id: "b", state: .done, at: 200))
        try s.upsert(sampleTap(id: "c", state: .pending, at: 300))
        #expect(try s.taps(states: [.pending]).map(\.id) == ["c", "a"])
        #expect(try s.taps(states: [.pending, .done]).count == 3)
    }

    @Test func lastShownPerWatcher() throws {
        let s = try Store.inMemory()
        try s.upsert(sampleTap(id: "a", watcher: .bin, at: 100))
        try s.upsert(sampleTap(id: "b", watcher: .bin, at: 500))
        #expect(try s.lastShown(watcher: .bin) == Date(timeIntervalSince1970: 500))
        #expect(try s.lastShown(watcher: .tabs) == nil)
    }

    @Test func firstSeenIsSticky() throws {
        let s = try Store.inMemory()
        let u = URL(string: "https://example.com/a")!
        #expect(try s.firstSeen(url: u, now: Date(timeIntervalSince1970: 10)) == Date(timeIntervalSince1970: 10))
        #expect(try s.firstSeen(url: u, now: Date(timeIntervalSince1970: 99)) == Date(timeIntervalSince1970: 10))
    }

    @Test func journalForTap() throws {
        let s = try Store.inMemory()
        let m = FileMove(from: URL(fileURLWithPath: "/a"), to: URL(fileURLWithPath: "/b"))
        try s.appendJournal(JournalEntry(tapID: "t1", move: m, at: Date(timeIntervalSince1970: 1)))
        try s.appendJournal(JournalEntry(tapID: "t2", move: m, at: Date(timeIntervalSince1970: 2)))
        #expect(try s.journal(tapID: "t1").count == 1)
    }

    @Test func settings() throws {
        let s = try Store.inMemory()
        #expect(try s.setting("tabs.minAgeSeconds") == nil)
        try s.setSetting("tabs.minAgeSeconds", "60")
        #expect(try s.setting("tabs.minAgeSeconds") == "60")
    }

    @Test func persistsOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = dir.appendingPathComponent("s.sqlite")
        try Store(path: path).upsert(sampleTap())
        #expect(try Store(path: path).tap(id: "t1") != nil)
    }
}
