import Foundation

public enum ClaudeJobError: Error, Equatable {
    case notInstalled
    case failed(String)
    case noTable
}

/// The "tabs → comparison note" job: what Claude Code is asked, how its stream is shown, and how its answer is cleaned.
public enum ClaudeJob {
    public static func prompt(topic: String, tabs: [Tab]) -> String {
        let pages = tabs.enumerated().map { "\($0.offset + 1). \($0.element.url.absoluteString)" }.joined(separator: "\n")
        return """
            Read these \(tabs.count) pages with WebFetch and compare the products or options they describe, \
            for someone deciding about \(topic). Reply with ONLY one HTML <table>: the first column is the option's name \
            linked to its page, then 4-6 columns chosen for this decision (for example price, size, key feature, warranty), \
            one row per option. Write "not listed" when a page doesn't say. No text outside the table.

            \(pages)
            """
    }

    /// Headless Claude Code, streaming JSON, allowed to fetch web pages and nothing else.
    public static func arguments(prompt: String) -> [String] {
        ["-p", prompt, "--output-format", "stream-json", "--verbose", "--allowedTools", "WebFetch", "--max-turns", "12"]
    }

    /// A human line for the watchable Terminal window, or nil for events worth hiding.
    public static func progressLine(_ jsonLine: String) -> String? {
        guard let obj = object(jsonLine), let type = obj["type"] as? String else { return nil }
        switch type {
        case "assistant":
            let content = ((obj["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            for block in content {
                if block["type"] as? String == "tool_use", block["name"] as? String == "WebFetch" {
                    let url = ((block["input"] as? [String: Any])?["url"] as? String).flatMap(URL.init(string:))
                    return "Reading \(url?.host ?? "a page")…"
                }
                if block["type"] as? String == "text", let text = block["text"] as? String {
                    let line = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? ""
                    guard !line.isEmpty, !line.hasPrefix("<") else { return nil }
                    return line.count > 80 ? String(line.prefix(79)) + "…" : line
                }
            }
            return nil
        case "result":
            if obj["is_error"] as? Bool == true { return "Claude stopped: \(obj["result"] as? String ?? obj["subtype"] as? String ?? "error")" }
            return "Done. Table ready."
        default:
            return nil
        }
    }

    /// Claude's final answer, from the stream's "result" event.
    public static func finalText(_ jsonLines: [String]) throws -> String {
        guard let result = jsonLines.compactMap(object).last(where: { $0["type"] as? String == "result" }) else {
            throw ClaudeJobError.failed("Claude ended without a result")
        }
        if result["is_error"] as? Bool == true {
            throw ClaudeJobError.failed(result["result"] as? String ?? result["subtype"] as? String ?? "error")
        }
        return result["result"] as? String ?? ""
    }

    /// The first <table>…</table> in the text.
    public static func extractTable(_ text: String) throws -> String {
        guard let start = text.range(of: "<table", options: .caseInsensitive),
              let end = text.range(of: "</table>", options: [.caseInsensitive, .backwards]),
              start.lowerBound < end.upperBound else { throw ClaudeJobError.noTable }
        return String(text[start.lowerBound..<end.upperBound])
    }

    static let allowed: Set<String> = ["table", "thead", "tbody", "tr", "th", "td", "b", "strong", "i", "em", "a", "br", "h2", "h3", "p", "ul", "ol", "li"]
    static let dropWithContent: Set<String> = ["script", "style", "iframe", "object", "svg", "noscript"]

    /// Keeps only simple table markup; links only with http(s) hrefs; every other tag and attribute is dropped.
    public static func sanitize(_ html: String) -> String {
        var out = ""
        var i = html.startIndex
        var skipping: String?
        while i < html.endIndex {
            if html[i] == "<", let close = html[i...].firstIndex(of: ">") {
                let inner = String(html[html.index(after: i)..<close])
                i = html.index(after: close)
                if inner.hasPrefix("!") { continue }
                let closing = inner.hasPrefix("/")
                let body = closing ? String(inner.dropFirst()) : inner
                let name = body.prefix { $0.isLetter || $0.isNumber }.lowercased()
                if let s = skipping { if closing && name == s { skipping = nil }; continue }
                if dropWithContent.contains(name) { if !closing { skipping = name }; continue }
                guard allowed.contains(name) else { continue }
                if closing { if name != "br" { out += "</\(name)>" }; continue }
                if name == "a", let href = attribute("href", in: body), let url = URL(string: href),
                   ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    out += "<a href=\"\(escape(href))\">"
                } else {
                    out += "<\(name)>"
                }
                continue
            }
            if skipping == nil { out.append(html[i] == "<" ? "&lt;" : String(html[i])) }
            i = html.index(after: i)
        }
        return out
    }

    /// Where `claude` lives, if installed.
    public static func locate() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in path + ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"] {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("claude")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // MARK: - helpers

    static func object(_ line: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for g in 2...4 {
            if let r = Range(m.range(at: g), in: tag) {
                return String(tag[r]).replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        return nil
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}


/// The watchable research job: headless Claude Code reads the pages (WebFetch only) and returns a short HTML note.
/// Works with the user's API key or, for development and demos, the subscription token.
public enum ResearchJob {
    public static func prompt(urls: [String], goal: String) -> String {
        """
        The user had these pages open: \(urls.joined(separator: " , ")).
        Goal: \(goal)
        Read every page with WebFetch. Then write a short note that lets the user pick this up later, in under 180 words:
        one <h2> per page or theme with 1-3 <li> key points each (link each page with <a>), then <h2>Open questions</h2> and <h2>Next step</h2>.
        Use only h2, p, ul, li, b, a. Reply with ONLY the HTML, nothing before or after it.
        """
    }

    /// Runs the job, reporting human progress lines ("Reading techrepublic.com…"). Returns sanitized HTML.
    /// With an API key it uses the Messages API's web_fetch tool (nothing else to install); otherwise headless Claude Code.
    public static func run(urls: [String], goal: String, progress: @escaping @Sendable (String) -> Void) async throws -> String {
        if let key = Keychain.read(Keychain.apiKeyService) {
            return try await viaAPI(key: key, urls: urls, goal: goal, progress: progress)
        }
        return try await viaCLI(urls: urls, goal: goal, progress: progress)
    }

    static func viaAPI(key: String, urls: [String], goal: String, progress: @escaping @Sendable (String) -> Void,
                       transport: HTTPTransport = URLSessionTransport()) async throws -> String {
        var messages: [[String: Any]] = [["role": "user", "content": prompt(urls: urls, goal: goal)]]
        progress("Claude is reading \(urls.count) pages")
        for _ in 0..<5 {
            let body: [String: Any] = ["model": "claude-sonnet-5-5", "max_tokens": 2500, "messages": messages,
                                       "tools": [["type": "web_fetch_20260209", "name": "web_fetch", "max_uses": max(3, urls.count + 2)]]]
            let data = try await transport.post(URL(string: "https://api.anthropic.com/v1/messages")!,
                                                headers: ["x-api-key": key, "anthropic-version": "2023-06-01"],
                                                body: try JSONSerialization.data(withJSONObject: body), timeout: 240)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeJobError.failed("Unreadable answer") }
            let content = obj["content"] as? [[String: Any]] ?? []
            for b in content where b["type"] as? String == "server_tool_use" {
                if let u = (b["input"] as? [String: Any])?["url"] as? String { progress("Read \(URL(string: u)?.host ?? "a page")") }
            }
            if obj["stop_reason"] as? String == "pause_turn" {   // long server-tool turn: send it back to continue
                messages.append(["role": "assistant", "content": content])
                continue
            }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
            let html = ClaudeJob.sanitize(text)
            guard html.contains("<") else { throw ClaudeJobError.failed("Claude didn't write the note.") }
            return html
        }
        throw ClaudeJobError.failed("Claude took too long reading the pages.")
    }

    static func viaCLI(urls: [String], goal: String, progress: @escaping @Sendable (String) -> Void) async throws -> String {
        guard let claude = Shell.which("claude") else { throw ClaudeJobError.notInstalled }
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CONFIG_DIR"] = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sparehand-claude").path
        if let token = Keychain.read(Keychain.oauthService) { env["CLAUDE_CODE_OAUTH_TOKEN"] = token; env.removeValue(forKey: "ANTHROPIC_API_KEY") }
        else { throw ClaudeJobError.failed("Connect Claude first.") }
        let args = ["-p", prompt(urls: urls, goal: goal), "--output-format", "stream-json", "--verbose",
                    "--allowedTools", "WebFetch", "--tools", "WebFetch", "--max-turns", "14",
                    "--setting-sources", "", "--no-session-persistence", "--model", "claude-sonnet-5-5"]
        let lines: [String] = try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: claude)
            p.arguments = args
            p.environment = env
            p.currentDirectoryURL = URL(fileURLWithPath: "/private/tmp")
            let out = Pipe()
            p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
            try p.run()
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: killer)
            var all: [String] = [], buffer = Data()
            let h = out.fileHandleForReading
            while true {
                let chunk = h.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    all.append(line)
                    if let human = ClaudeJob.progressLine(line), !human.hasPrefix("Done") { progress(human) }
                }
            }
            p.waitUntilExit(); killer.cancel()
            return all
        }.value
        let text = try ClaudeJob.finalText(lines)
        let html = ClaudeJob.sanitize(text)
        guard html.contains("<") else { throw ClaudeJobError.failed("Claude didn't write the note.") }
        return html
    }

    /// Splits note HTML into blocks to write one at a time (a heading, a list, a paragraph).
    public static func blocks(_ html: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "<(h2|h3|p|ul|ol|table)>[\\s\\S]*?</\\1>", options: [.caseInsensitive])
        let found = re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { Range($0.range, in: html).map { String(html[$0]) } }
        return found.isEmpty ? [html] : found
    }
}
