import CoreGraphics
import Foundation

/// Opens and places Terminal windows that Sparehand owns, always addressed by window id.
public struct TerminalLauncher: Sendable {
    let runner: ScriptRunner
    public init(runner: ScriptRunner) { self.runner = runner }

    /// A new window (never an existing one) running `command`; returns its window id.
    public static func openScript(command: String, title: String) -> String {
        """
        tell application "Terminal"
          set t to do script \(AppleScriptText.quoted(command))
          set custom title of t to \(AppleScriptText.quoted(title))
          repeat with w in windows
            if selected tab of w is t then return id of w
          end repeat
          return -1
        end tell
        """
    }

    public func open(command: String, title: String) async throws -> Int {
        let out = try await runner.run(Self.openScript(command: command, title: title))
        guard let id = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)), id > 0 else {
            throw ScriptError(code: -1, message: "Terminal did not report its new window")
        }
        return id
    }

    public func setBounds(windowID: Int, _ rect: CGRect) async throws {
        _ = try await runner.run("tell application \"Terminal\" to set bounds of window id \(windowID) to \(Self.bounds(rect))")
    }

    public func close(windowID: Int) async throws {
        _ = try await runner.run("tell application \"Terminal\" to close window id \(windowID)")
    }

    /// AppleScript bounds: {left, top, right, bottom} in global screen points.
    public static func bounds(_ r: CGRect) -> String {
        "{\(Int(r.minX)), \(Int(r.minY)), \(Int(r.maxX)), \(Int(r.maxY))}"
    }
}
