import Foundation
import Testing
@testable import SparehandCore

@Suite struct ModelTests {
    @Test func candidateRoundTrips() throws {
        let c = Candidate(id: "abc", origin: .claude, why: "25 screenshots",
                          evidence: [EvidenceItem(label: "l", detail: "d")],
                          steps: [ToolCall(tool: "sort_by_content", args: .object(["files": .object(["folder": .string("Desktop")]),
                                                                                   "folders": .array([.string("Travel")])]))],
                          noticedAt: Date(timeIntervalSince1970: 1_800_000_000), repeatTitle: "{count} new screenshots")
        let back = try JSONDecoder().decode(Candidate.self, from: JSONEncoder().encode(c))
        #expect(back == c)
    }

    @Test func fingerprintIsOrderIndependent() {
        let a = Fingerprint.make("sort", ["b", "a"])
        #expect(a == Fingerprint.make("sort", ["a", "b"]))
        #expect(a.count == 16)
        #expect(a != Fingerprint.make("bin", ["a", "b"]))
    }

    @Test func everyToolIsReversible() {
        let c = Candidate(id: "x", origin: .claude, why: "", steps: Tools.all.map { ToolCall(tool: $0.name, args: .object([:])) }, noticedAt: Date())
        #expect(c.isReversible)
        let unknown = Candidate(id: "y", origin: .claude, why: "", steps: [ToolCall(tool: "rm_rf", args: .null)], noticedAt: Date())
        #expect(!unknown.isReversible)
    }
}
