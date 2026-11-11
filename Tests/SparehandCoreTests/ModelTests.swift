import Foundation
import Testing
@testable import SparehandCore

@Suite struct ModelTests {
    let tab = Tab(browser: "Google Chrome", title: "Best standing desks", url: URL(string: "https://example.com/desks")!)

    @Test func candidateRoundTrips() throws {
        let plans: [ActionPlan] = [
            .moveFiles([FileMove(from: URL(fileURLWithPath: "/a.png"), to: URL(fileURLWithPath: "/b/a.png"))]),
            .deletePermanently([URL(fileURLWithPath: "/t/x.dmg")]),
            .tabsToNote(topic: "Standing Desks", tabs: [tab]),
        ]
        for plan in plans {
            let c = Candidate(id: "abc", watcher: .tabs, summary: "s", facts: ["count": "7"],
                              evidence: [EvidenceItem(label: "l", detail: "d")], plan: plan,
                              noticedAt: Date(timeIntervalSince1970: 1_800_000_000))
            let back = try JSONDecoder().decode(Candidate.self, from: JSONEncoder().encode(c))
            #expect(back == c)
        }
    }

    @Test func fingerprintIsOrderIndependent() {
        let a = Fingerprint.make(.screenshots, ["b", "a"])
        #expect(a == Fingerprint.make(.screenshots, ["a", "b"]))
        #expect(a.count == 16)
        #expect(a != Fingerprint.make(.bin, ["a", "b"]))
    }

    @Test func reversibility() {
        #expect(ActionPlan.moveFiles([]).isReversible)
        #expect(!ActionPlan.deletePermanently([]).isReversible)
        #expect(ActionPlan.tabsToNote(topic: "x", tabs: []).isReversible)
    }
}
