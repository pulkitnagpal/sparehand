import Foundation
import Testing
@testable import SparehandCore

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    var reply: Result<Data, Error>
    var lastBody: Data?
    init(_ reply: Result<Data, Error>) { self.reply = reply }
    func post(_ url: URL, body: Data, timeout: TimeInterval) async throws -> Data {
        lastBody = body
        return try reply.get()
    }
    static func content(_ text: String) -> FakeTransport {
        let payload: [String: Any] = ["choices": [["message": ["role": "assistant", "content": text]]]]
        return FakeTransport(.success(try! JSONSerialization.data(withJSONObject: payload)))
    }
}

struct Down: Error {}

let screenshotCandidate = Candidate(id: "c1", watcher: .screenshots,
    summary: "120 screenshots are on the Desktop, oldest from June 2026; 3 recent ones would stay.",
    facts: ["count": "120", "kept": "3", "oldestMonth": "June 2026"], evidence: [], plan: .moveFiles([]), noticedAt: Date())
let binCandidate = Candidate(id: "c2", watcher: .bin, summary: "The Bin holds 12.4 GB; the 3 largest items are 11.3 GB.",
    facts: ["totalGB": "12.4 GB", "itemsGB": "11.3 GB", "n": "3"], evidence: [], plan: .deletePermanently([]), noticedAt: Date())
let tabsCandidate = Candidate(id: "c3", watcher: .tabs, summary: "7 open tabs about Standing Desks, open since Monday.",
    facts: ["count": "7", "topic": "Standing Desks", "since": "Monday"], evidence: [], plan: .tabsToNote(topic: "Standing Desks", tabs: []), noticedAt: Date())

@Suite struct JudgeTests {
    @Test func parsesModelVerdict() async throws {
        let t = FakeTransport.content(#"Sure: {"show": true, "value": 4, "title": "Tidy your Desktop", "body": "Move 120 screenshots into folders by month.", "action": "Tidy up"}"#)
        let v = try await LocalModelJudge(transport: t).verdict(for: screenshotCandidate)
        #expect(v == Verdict(show: true, value: 4, title: "Tidy your Desktop", body: "Move 120 screenshots into folders by month.", actionLabel: "Tidy up", source: .model))
    }

    @Test func fallsBackWhenServerDown() async {
        let j = FallbackJudge(primary: LocalModelJudge(transport: FakeTransport(.failure(Down()))))
        let v = await j.verdict(for: screenshotCandidate)
        #expect(v.source == .rules)
        #expect(v.show)
    }

    @Test func fallsBackOnBadJSON() async {
        let j = FallbackJudge(primary: LocalModelJudge(transport: FakeTransport.content("I think yes")))
        #expect(await j.verdict(for: binCandidate).source == .rules)
    }

    @Test func modelCanDecline() async {
        let t = FakeTransport.content(#"{"show": false, "value": 1, "title": "", "body": "", "action": "none"}"#)
        let v = await FallbackJudge(primary: LocalModelJudge(transport: t)).verdict(for: binCandidate)
        #expect(v.source == .model && !v.show)
    }

    @Test func requestDisablesThinking() async throws {
        let t = FakeTransport.content(#"{"show": true, "value": 3, "title": "a", "body": "b", "action": "c"}"#)
        _ = try await LocalModelJudge(transport: t).verdict(for: tabsCandidate)
        let sent = try #require(t.lastBody)
        let body = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect((body["chat_template_kwargs"] as? [String: Any])?["enable_thinking"] as? Bool == false)
        #expect(body["temperature"] as? Double == 0)
        #expect(body["model"] as? String == "mlx-community/Qwen3.5-4B-MLX-4bit")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.last?["content"]?.contains("Standing Desks") == true)
    }

    @Test func rejectsCopyThatContradictsPlan() async {
        // Seen live: the model said screenshots would go "to trash" when the plan only moves them into folders.
        let t = FakeTransport.content(#"{"show": true, "value": 4, "title": "25 old screenshots on Desktop", "body": "Move 25 screenshots to trash to free space.", "action": "Move"}"#)
        let v = await FallbackJudge(primary: LocalModelJudge(transport: t)).verdict(for: screenshotCandidate)
        #expect(v.source == .rules)
    }

    @Test func promptStatesWhereFilesGo() {
        let u = JudgePrompt.user(screenshotCandidate)
        #expect(u.contains("Pictures › Screenshots") && u.contains("nothing is deleted"))
    }

    @Test func ruleCopyPerWatcher() async {
        let r = RuleJudge()
        let s = await r.verdict(for: screenshotCandidate)
        #expect(s == Verdict(show: true, value: 3, title: "Tidy 120 screenshots", body: "Move them into Pictures › Screenshots by month. Undo any time.", actionLabel: "Tidy up", source: .rules))
        let b = await r.verdict(for: binCandidate)
        #expect(b.title == "Your Bin is holding 12.4 GB")
        #expect(b.body == "3 big items make up 11.3 GB. Emptying can't be undone.")
        #expect(b.actionLabel == "Empty 3")
        let t = await r.verdict(for: tabsCandidate)
        #expect(t.title == "7 tabs about Standing Desks")
        #expect(t.actionLabel == "Make the note")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPAREHAND_LIVE_JUDGE"] == "1"))
    func liveServerSmoke() async throws {
        let v = try await LocalModelJudge(timeout: 30).verdict(for: screenshotCandidate)
        print("live verdict:", v)
        #expect(v.source == .model)
    }
}
