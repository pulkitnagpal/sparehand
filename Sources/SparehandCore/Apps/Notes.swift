import CoreGraphics
import Foundation

/// Creates, shows and deletes notes in Apple Notes.
public struct NotesWriter: Sendable {
    let runner: ScriptRunner
    public init(runner: ScriptRunner) { self.runner = runner }

    /// The note goes in the default account's "Notes" folder (or its first folder). Its first line is the title.
    public static func createScript(title: String, html: String) -> String {
        let body = "<h1>\(escapeHTML(title))</h1>" + html
        return """
        tell application "Notes"
          set acc to default account
          if exists folder "Notes" of acc then
            set f to folder "Notes" of acc
          else
            set f to folder 1 of acc
          end if
          set n to make new note at f with properties {body:\(AppleScriptText.quoted(body))}
          return id of n
        end tell
        """
    }

    public func create(title: String, html: String) async throws -> String {
        try await runner.run(Self.createScript(title: title, html: html)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func delete(noteID: String) async throws {
        _ = try await runner.run("tell application \"Notes\" to delete note id \(AppleScriptText.quoted(noteID))")
    }

    /// How many Notes windows the user already has (0 when Notes isn't running; asks nothing then).
    public func userWindowCount(notesRunning: Bool) async -> Int {
        guard notesRunning else { return 0 }
        return Int((try? await runner.run("tell application \"Notes\" to count windows")) ?? "") ?? 1
    }

    /// Opens the note in a window Sparehand may place, but only if the user had no Notes windows open
    /// (Notes can't open a second window from a script, and the user's window is off limits). Returns that window's id.
    public func show(noteID: String, ifNoUserWindows windowsBefore: Int) async throws -> Int? {
        guard windowsBefore == 0 else { return nil }
        let out = try await runner.run("""
            tell application "Notes"
              show note id \(AppleScriptText.quoted(noteID))
              activate
              return id of window 1
            end tell
            """)
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func setBounds(windowID: Int, _ rect: CGRect) async throws {
        _ = try await runner.run("tell application \"Notes\" to set bounds of window id \(windowID) to \(TerminalLauncher.bounds(rect))")
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
