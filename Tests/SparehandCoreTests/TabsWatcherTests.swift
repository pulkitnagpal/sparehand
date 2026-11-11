import Foundation
import Testing
@testable import SparehandCore

@Suite struct TopicGroupingTests {
    let g = TopicGrouper()

    @Test func groupsMBA() {
        let titles = ["MBA Canada rankings 2026", "Kubernetes pod OOMKilled fix", "Rotman MBA tuition",
                      "Stack Overflow: docker memory limit", "UBC Sauder MBA admissions"]
        let groups = g.groups(titles, minSize: 3)
        #expect(groups.count == 1)
        #expect(groups.first?.members == [0, 2, 4])
        #expect(groups.first?.topic == "MBA")
    }

    @Test func groupsGoaNotReact() {
        let titles = ["Flights Delhi to Goa Dec 20", "Goa beach hotels", "React useEffect cleanup",
                      "Goa itinerary 4 days", "React StrictMode double render"]
        let groups = g.groups(titles, minSize: 3)
        #expect(groups.map(\.members) == [[0, 1, 3]])
        #expect(groups.first?.topic == "Goa")
        #expect(g.groups(titles, minSize: 2).count == 2)
    }

    @Test func prefersPhraseAndPlurals() {
        let titles = ["Best standing desks 2026 – Wirecutter", "Standing desk buying guide", "Uplift V2 standing desk review",
                      "FlexiSpot E7 Pro standing desk", "Are standing desks worth it?", "Weather today"]
        let group = try! #require(g.groups(titles, minSize: 5).first)
        #expect(group.members == [0, 1, 2, 3, 4])
        #expect(group.topic == "Standing Desks")
    }

    @Test func ignoresGenericWords() {
        let titles = ["Best pizza near me", "Best running shoes", "Best laptops 2026", "Best VPN review", "Best headphones"]
        #expect(g.groups(titles, minSize: 5).isEmpty)
    }
}

@Suite struct TabsWatcherTests {
    let now = Date(timeIntervalSince1970: 1_794_000_000)
    let deskTitles = ["Best standing desks 2026", "Standing desk buying guide", "Uplift V2 standing desk review",
                      "FlexiSpot E7 standing desk", "Are standing desks worth it?"]

    func runner() -> RecordingRunner {
        RecordingRunner(reply: deskTitles.enumerated().map { "\($1)\u{1F}https://site\($0).com/desk\u{1E}" }.joined())
    }

    func env(store: Store, at date: Date) throws -> Environment {
        var e = Environment(home: FileManager.default.temporaryDirectory, now: { date }, store: store, scripts: runner())
        e.runningApps = { ["Google Chrome"] }
        return e
    }

    @Test func respectsMinAge() async throws {
        let s = try Store.inMemory()
        let w = TabsWatcher(minTabs: 5, minAge: 3600)
        #expect(try await w.candidates(env(store: s, at: now)).isEmpty)          // first seen now
        let c = try #require(try await w.candidates(env(store: s, at: now.addingTimeInterval(7200))).first)
        guard case .tabsToNote(let topic, let tabs) = c.plan else { Issue.record("plan"); return }
        #expect(topic == "Standing Desks" && tabs.count == 5)
        #expect(c.facts["count"] == "5" && c.facts["topic"] == "Standing Desks")
        #expect(c.watcher == .tabs)
        #expect(c.evidence.count == 3)
    }

    @Test func minAgeFromSetting() async throws {
        let s = try Store.inMemory()
        try s.setSetting("tabs.minAgeSeconds", "60")
        let w = TabsWatcher(minTabs: 5, minAge: 6 * 3600)
        _ = try await w.candidates(env(store: s, at: now))
        #expect(try await w.candidates(env(store: s, at: now.addingTimeInterval(120))).count == 1)
    }

    @Test func noBrowsersNoCandidates() async throws {
        var e = try env(store: Store.inMemory(), at: now)
        e.runningApps = { [] }
        #expect(try await TabsWatcher(minTabs: 5, minAge: 0).candidates(e).isEmpty)
    }
}
