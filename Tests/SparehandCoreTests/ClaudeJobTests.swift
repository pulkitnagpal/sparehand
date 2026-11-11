import Foundation
import Testing
@testable import SparehandCore

@Suite struct ClaudeJobTests {
    var lines: [String] {
        let url = Bundle.module.url(forResource: "claude-stream", withExtension: "jsonl", subdirectory: "Fixtures")!
        return try! String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }
    let tabs = [Tab(browser: "Arc", title: "Best standing desks", url: URL(string: "https://a.com/desks")!),
                Tab(browser: "Arc", title: "Uplift V2", url: URL(string: "https://b.com/uplift")!)]

    @Test func promptListsPagesAndAsksForTableOnly() {
        let p = ClaudeJob.prompt(topic: "Standing Desks", tabs: tabs)
        #expect(p.contains("1. https://a.com/desks") && p.contains("2. https://b.com/uplift"))
        #expect(p.contains("Standing Desks") && p.contains("ONLY one HTML <table>"))
    }

    @Test func argumentsRestrictTools() {
        let a = ClaudeJob.arguments(prompt: "P")
        #expect(a == ["-p", "P", "--output-format", "stream-json", "--verbose", "--allowedTools", "WebFetch", "--max-turns", "12"])
    }

    @Test func progressFromFixture() {
        let shown = lines.compactMap(ClaudeJob.progressLine)
        #expect(shown == ["I'll read each page and compare the desks.", "Reading www.nytimes.com…", "Reading www.upliftdesk.com…", "Done. Table ready."])
    }

    @Test func finalTextFromResult() throws {
        #expect(try ClaudeJob.finalText(lines).contains("<table>"))
    }

    @Test func errorResultThrows() {
        let bad = [#"{"type":"result","subtype":"error_max_turns","is_error":true,"result":"Reached max turns"}"#]
        #expect(throws: ClaudeJobError.failed("Reached max turns")) { try ClaudeJob.finalText(bad) }
        #expect(ClaudeJob.progressLine(bad[0]) == "Claude stopped: Reached max turns")
        #expect(throws: ClaudeJobError.failed("Claude ended without a result")) { try ClaudeJob.finalText([]) }
    }

    @Test func extractsTable() throws {
        let t = try ClaudeJob.extractTable("Sure!\n<TABLE border=1><tr><td>x</td></tr></TABLE> thanks")
        #expect(t == "<TABLE border=1><tr><td>x</td></tr></TABLE>")
    }

    @Test func noTableThrows() {
        #expect(throws: ClaudeJobError.noTable) { try ClaudeJob.extractTable("I couldn't read the pages.") }
    }

    @Test func sanitizeStripsScriptsAndAttributes() {
        let dirty = #"<table onclick="x" style="color:red"><tr><td><script>alert(1)</script><a href="javascript:x">y</a> <a href="https://ok.com/a?b=1&c=2" target="_blank">ok</a><img src=x onerror=y><b>bold</b></td></tr></table>"#
        let clean = ClaudeJob.sanitize(dirty)
        #expect(!clean.lowercased().contains("script"))
        #expect(!clean.contains("onclick") && !clean.contains("style") && !clean.contains("onerror") && !clean.contains("<img"))
        #expect(!clean.contains("javascript:"))
        #expect(clean.contains(#"<a href="https://ok.com/a?b=1&amp;c=2">ok</a>"#))
        #expect(clean.contains("<b>bold</b>"))
        #expect(clean.hasPrefix("<table>"))
    }
}
