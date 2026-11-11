import Foundation

/// A JSON value that is Codable and Sendable, for tool arguments that come from a model.
public enum JSONValue: Codable, Sendable, Equatable, Hashable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    /// From JSONSerialization output.
    public init(any: Any?) {
        switch any {
        case let s as String: self = .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let a as [Any]: self = .array(a.map { JSONValue(any: $0) })
        case let o as [String: Any]: self = .object(o.mapValues { JSONValue(any: $0) })
        default: self = .null
        }
    }

    public subscript(key: String) -> JSONValue? { if case .object(let o) = self { return o[key] }; return nil }
    public var string: String? { if case .string(let s) = self { return s }; if case .number(let n) = self { return String(n) }; return nil }
    public var number: Double? { if case .number(let n) = self { return n }; if case .string(let s) = self { return Double(s) }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var strings: [String] { array?.compactMap(\.string) ?? (string.map { [$0] } ?? []) }
}

/// Runs a command and returns stdout (empty on failure or timeout).
public enum Shell {
    public static func run(_ path: String, _ args: [String], env: [String: String]? = nil, cwd: String? = nil, timeout: TimeInterval = 15) -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let env { p.environment = env }
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        var data = Data()
        let reader = DispatchQueue(label: "shell.read")
        let group = DispatchGroup()
        group.enter()
        reader.async { data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        DispatchQueue.global().async { _ = err.fileHandleForReading.readDataToEndOfFile() }
        if group.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return "" }
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// First executable named `name` on PATH or the usual install places.
    public static func which(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in path + ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let c = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        return nil
    }
}

/// Strips anything that looks like a secret before it is stored or sent anywhere.
public enum Redactor {
    static let patterns = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
        #"sk-ant-[A-Za-z0-9_\-]{10,}"#, #"sk-[A-Za-z0-9_\-]{16,}"#, #"(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"#,
        #"github_pat_[A-Za-z0-9_]{20,}"#, #"AKIA[0-9A-Z]{16}"#, #"ASIA[0-9A-Z]{16}"#, #"xox[abprs]-[A-Za-z0-9\-]{10,}"#,
        #"AIza[0-9A-Za-z_\-]{30,}"#, #"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#,
        #"glpat-[A-Za-z0-9_\-]{16,}"#, #"npm_[A-Za-z0-9]{30,}"#,
        #"(?:password|passwd|pwd|secret|token|api[_\-]?key|apikey|auth|authorization|bearer|private[_\-]?key|access[_\-]?key|client[_\-]?secret)["']?\s*[:=]\s*["']?(?:(?:bearer|basic|token)\s+)?[^\s"',;]{4,}"#,
        #"bearer\s+[A-Za-z0-9_\-\.=]{12,}"#,
        #"(?=[A-Za-z0-9+_]*\d)(?=[A-Za-z0-9+_]*[A-Za-z])[A-Za-z0-9+_]{32,}={0,2}"#,
    ]
    static let secret = try! NSRegularExpression(pattern: patterns.map { "(?:\($0))" }.joined(separator: "|"), options: [.caseInsensitive])
    static let urlCreds = try! NSRegularExpression(pattern: #"(https?://)[^/\s:@]+:[^/\s@]+@"#)
    static let export = try! NSRegularExpression(pattern: #"\b(export\s+[A-Z0-9_]+)=\S+"#, options: [.caseInsensitive])

    public static func text(_ s: String) -> String {
        var t = replace(urlCreds, in: s, with: "$1[REDACTED]@")
        t = replace(export, in: t, with: "$1=[REDACTED]")
        return replace(secret, in: t, with: "[REDACTED]")
    }

    /// Host and path only: queries and fragments often carry tokens.
    public static func url(_ u: String) -> String {
        let base = u.split(separator: "#", maxSplits: 1).first.map(String.init) ?? u
        return String(text(base.split(separator: "?", maxSplits: 1).first.map(String.init) ?? base).prefix(160))
    }

    static func replace(_ re: NSRegularExpression, in s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}
