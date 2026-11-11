import Foundation

/// Runs AppleScript source and returns its result as text.
public protocol ScriptRunner: Sendable {
    func run(_ source: String) async throws -> String
}

/// Placeholder until the real runner lands (Task 7).
public struct OSAScriptRunner: ScriptRunner {
    public init() {}
    public func run(_ source: String) async throws -> String { "" }
}
