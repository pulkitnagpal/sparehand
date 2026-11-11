import Foundation

/// Runs AppleScript source and returns its result as text.
public protocol ScriptRunner: Sendable {
    func run(_ source: String) async throws -> String
}

public struct ScriptError: Error, Sendable, Equatable {
    /// -1743: the user hasn't allowed Sparehand to control that app (Automation).
    public var code: Int
    public var message: String
    public init(code: Int, message: String) { self.code = code; self.message = message }
}

/// Runs scripts through /usr/bin/osascript (safe from any thread; one process per call).
public struct OSAScriptRunner: ScriptRunner {
    /// A frozen app (or a permission prompt nobody has answered) must never stall Sparehand.
    public var timeout: TimeInterval
    public init(timeout: TimeInterval = 8) { self.timeout = timeout }

    public func run(_ source: String) async throws -> String {
        let timeout = self.timeout
        return try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-"]
            let input = Pipe(), output = Pipe(), errors = Pipe()
            p.standardInput = input; p.standardOutput = output; p.standardError = errors
            try p.run()
            input.fileHandleForWriting.write(Data(source.utf8))
            try input.fileHandleForWriting.close()
            let deadline = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            defer { deadline.cancel() }
            let out = output.fileHandleForReading.readDataToEndOfFile()
            let err = errors.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationReason == .uncaughtSignal { throw ScriptError(code: -1712, message: "The app didn't answer in time.") }
            if p.terminationStatus != 0 {
                let message = String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw ScriptError(code: Self.code(in: message), message: message)
            }
            var text = String(decoding: out, as: UTF8.self)
            if text.hasSuffix("\n") { text.removeLast() }
            return text
        }.value
    }

    /// osascript errors end with "(-1743)".
    static func code(in message: String) -> Int {
        guard let open = message.lastIndex(of: "("), let close = message.lastIndex(of: ")"), open < close else { return -1 }
        return Int(message[message.index(after: open)..<close]) ?? -1
    }
}

public enum AppleScriptText {
    /// A double-quoted AppleScript string literal.
    public static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
