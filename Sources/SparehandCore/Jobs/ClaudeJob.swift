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
