import Foundation
import Testing
@testable import SparehandCore

@Suite struct AppDriverTests {
    @Test func terminalScriptUsesNewWindow() {
        let s = TerminalLauncher.openScript(command: "echo hi", title: "Sparehand")
        #expect(s.contains("do script \"echo hi\""))
        let doLine = s.split(separator: "\n").first { $0.contains("do script") } ?? ""
        #expect(!doLine.contains(" in "))   // `do script … in window 1` would reuse a window, possibly the user's
        #expect(s.contains("custom title of t to \"Sparehand\""))
        #expect(s.contains("return id of w"))
    }

    @Test func terminalOpenReturnsWindowID() async throws {
        let r = RecordingRunner(reply: "4711")
        #expect(try await TerminalLauncher(runner: r).open(command: "x", title: "y") == 4711)
    }

    @Test func boundsTargetOneWindowByID() async throws {
        let r = RecordingRunner()
        try await TerminalLauncher(runner: r).setBounds(windowID: 42, CGRect(x: 1512, y: 90, width: 1200, height: 800))
        #expect(r.scripts.last == "tell application \"Terminal\" to set bounds of window id 42 to {1512, 90, 2712, 890}")
    }

    @Test func scriptsQuoteInput() {
        let s = TerminalLauncher.openScript(command: #"say "hi" \ there"#, title: #"a"b"#)
        #expect(s.contains(#"do script "say \"hi\" \\ there""#))
        #expect(s.contains(#"custom title of t to "a\"b""#))
    }

    @Test func notesCreateScriptHasTitleAndTable() {
        let s = NotesWriter.createScript(title: "Standing Desks", html: "<table><tr><td>x</td></tr></table>")
        #expect(s.contains("<h1>Standing Desks</h1><table><tr><td>x</td></tr></table>"))
        #expect(s.contains("make new note at f"))
        #expect(s.contains("return id of n"))
    }

    @Test func notesTitleIsEscaped() {
        let s = NotesWriter.createScript(title: "A <b> & \"C\"", html: "")
        #expect(s.contains(#"<h1>A &lt;b&gt; &amp; \"C\"</h1>"#))
    }

    @Test func notesSkipsShowWhenUserWindowsOpen() async throws {
        let r = RecordingRunner(reply: "9")
        let id = try await NotesWriter(runner: r).show(noteID: "x-coredata://1", ifNoUserWindows: 2)
        #expect(id == nil)
        #expect(r.scripts.isEmpty)
    }

    @Test func notesShowsWhenNoUserWindows() async throws {
        let r = RecordingRunner(reply: "9")
        #expect(try await NotesWriter(runner: r).show(noteID: "x-coredata://1", ifNoUserWindows: 0) == 9)
        #expect(r.scripts.first?.contains("show note id \"x-coredata://1\"") == true)
    }

    @Test func notesDeleteByID() async throws {
        let r = RecordingRunner()
        try await NotesWriter(runner: r).delete(noteID: "x-coredata://1")
        #expect(r.scripts == ["tell application \"Notes\" to delete note id \"x-coredata://1\""])
    }
}
