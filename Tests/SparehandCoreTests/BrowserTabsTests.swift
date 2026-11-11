import Foundation
import Testing
@testable import SparehandCore

@Suite struct BrowserTabsTests {
    @Test func parsesChromeRecords() {
        let out = "Best standing desks\u{1F}https://a.com/desks\u{1E}Uplift V2 review\u{1F}https://b.com/uplift\u{1E}"
        let tabs = BrowserTabs.parse(out, browser: "Arc")
        #expect(tabs == [Tab(browser: "Arc", title: "Best standing desks", url: URL(string: "https://a.com/desks")!),
                         Tab(browser: "Arc", title: "Uplift V2 review", url: URL(string: "https://b.com/uplift")!)])
    }

    @Test func parsesSafariRecordsAndSkipsJunk() {
        let out = "A\u{1F}https://a.com\u{1E}Empty url\u{1F}\u{1E}Settings\u{1F}chrome://settings\u{1E}"
        #expect(BrowserTabs.parse(out, browser: "Safari").map(\.title) == ["A"])
    }

    @Test func quotesAppleScript() {
        #expect(AppleScriptText.quoted(#"say "hi" \ bye"#) == #""say \"hi\" \\ bye""#)
    }

    @Test func listScriptTargetsTheApp() {
        #expect(BrowserTabs.listScript(app: "Google Chrome").contains(#"tell application "Google Chrome""#))
        #expect(BrowserTabs.safariListScript().contains("name of t"))
    }

    @Test func onlyAsksRunningBrowsers() async {
        let runner = RecordingRunner(reply: "T\u{1F}https://x.com\u{1E}")
        let tabs = await BrowserTabs.all(runner: runner, running: ["Arc", "Finder"])
        #expect(tabs.count == 1)
        #expect(runner.scripts.count == 1 && runner.scripts[0].contains(#"application "Arc""#))
    }

    @Test func deniedAutomationYieldsNoTabs() async {
        let tabs = await BrowserTabs.all(runner: FailingRunner(code: -1743), running: ["Google Chrome", "Safari"])
        #expect(tabs.isEmpty)
    }
}

final class RecordingRunner: ScriptRunner, @unchecked Sendable {
    var scripts: [String] = []
    let reply: String
    init(reply: String = "") { self.reply = reply }
    func run(_ source: String) async throws -> String { scripts.append(source); return reply }
}

struct FailingRunner: ScriptRunner {
    let code: Int
    func run(_ source: String) async throws -> String { throw ScriptError(code: code, message: "denied") }
}
