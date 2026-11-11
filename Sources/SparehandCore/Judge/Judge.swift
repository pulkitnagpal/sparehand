import Foundation

/// Decides whether a candidate is worth a tap and words the card. Never throws: there is always an answer.
public protocol Judge: Sendable {
    func verdict(for c: Candidate) async -> Verdict
}

public protocol HTTPTransport: Sendable {
    func post(_ url: URL, body: Data, timeout: TimeInterval) async throws -> Data
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func post(_ url: URL, body: Data, timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw JudgeError.http }
        return data
    }
}

public enum JudgeError: Error { case http, unparseable }

public enum JudgePrompt {
    public static let system = """
        You decide whether a Mac assistant should show the user a suggestion card.
        Show a card when there is a concrete, helpful action the user would likely approve: freeing wasted space or resources, \
        unblocking something that is waiting on them, preventing an embarrassment, or saving repeated manual work.
        Do NOT show a card when nothing is wrong, the thing is in active use, or the action would get in the way.
        Being busy is not a reason to stay quiet: cards are quiet and can be read later.
        Answer ONLY JSON: {"show": true|false, "value": 1-5, "title": "<=8 words", "body": "<=24 words", "action": "<=3 words"}

        Examples:
        Noticed: A node process has been idle for 3 days using 1.2 GB of memory. -> {"show": true, "value": 4, "title": "An idle process is using 1.2 GB", "body": "It has done nothing for 3 days. Quit it to free the memory?", "action": "Quit it"}
        Noticed: Spotify is using 300 MB of memory while music is playing. -> {"show": false, "value": 1, "title": "", "body": "", "action": "none"}
        Noticed: A Chrome upload failed 20 minutes ago. -> {"show": true, "value": 4, "title": "An upload failed", "body": "The upload in Chrome stopped 20 minutes ago. Retry it?", "action": "Retry"}
        """

    public static func user(_ c: Candidate) -> String {
        var lines = ["Noticed: \(c.summary)"]
        if !c.evidence.isEmpty {
            lines.append("Details: " + c.evidence.map { "\($0.label) (\($0.detail))" }.joined(separator: "; "))
        }
        switch c.plan {
        case .moveFiles: lines.append("Proposed action: move the files; undo is possible.")
        case .deletePermanently: lines.append("Proposed action: delete these items permanently; this cannot be undone.")
        case .tabsToNote(let topic, _): lines.append("Proposed action: turn the tabs about \(topic) into one comparison table in Notes.")
        }
        return lines.joined(separator: "\n")
    }
}

/// The local model behind mlx_lm.server. Throws on any problem so FallbackJudge can step in.
public struct LocalModelJudge: Sendable {
    let endpoint: URL
    let model: String
    let timeout: TimeInterval
    let transport: HTTPTransport

    public init(endpoint: URL = URL(string: "http://127.0.0.1:8765/v1/chat/completions")!,
                model: String = "mlx-community/Qwen3.5-4B-MLX-4bit",
                timeout: TimeInterval = 3,
                transport: HTTPTransport = URLSessionTransport()) {
        self.endpoint = endpoint; self.model = model; self.timeout = timeout; self.transport = transport
    }

    public func verdict(for c: Candidate) async throws -> Verdict {
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": JudgePrompt.system], ["role": "user", "content": JudgePrompt.user(c)]],
            "temperature": 0.0,
            "max_tokens": 160,
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        let data = try await transport.post(endpoint, body: try JSONSerialization.data(withJSONObject: body), timeout: timeout)
        guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (reply["choices"] as? [[String: Any]])?.first,
              let content = (choice["message"] as? [String: Any])?["content"] as? String,
              let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"),
              let obj = try JSONSerialization.jsonObject(with: Data(content[start...end].utf8)) as? [String: Any],
              let show = obj["show"] as? Bool
        else { throw JudgeError.unparseable }
        let title = (obj["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let text = (obj["body"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let action = (obj["action"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if show && (title.isEmpty || text.isEmpty || action.isEmpty) { throw JudgeError.unparseable }
        return Verdict(show: show, value: (obj["value"] as? Int) ?? 3, title: title, body: text, actionLabel: action, source: .model)
    }
}

/// Plain copy per watcher, used when the model isn't available. Always shows.
public struct RuleJudge: Judge {
    public init() {}
    public func verdict(for c: Candidate) async -> Verdict {
        let f = c.facts
        switch c.watcher {
        case .screenshots:
            return Verdict(show: true, value: 3, title: "Tidy \(f["count"] ?? "") screenshots",
                           body: "Move them into Pictures › Screenshots by month. Undo any time.", actionLabel: "Tidy up", source: .rules)
        case .bin:
            return Verdict(show: true, value: 3, title: "Your Bin is holding \(f["totalGB"] ?? "")",
                           body: "\(f["n"] ?? "") big items make up \(f["itemsGB"] ?? ""). Emptying can't be undone.",
                           actionLabel: "Empty \(f["n"] ?? "")", source: .rules)
        case .tabs:
            return Verdict(show: true, value: 3, title: "\(f["count"] ?? "") tabs about \(f["topic"] ?? "one topic")",
                           body: "Turn them into one comparison table in Notes?", actionLabel: "Make the note", source: .rules)
        }
    }
}

/// The local model first; plain rules if it's down, slow or talking nonsense.
public struct FallbackJudge: Judge {
    let primary: LocalModelJudge
    let fallback: RuleJudge

    public init(primary: LocalModelJudge, fallback: RuleJudge = RuleJudge()) {
        self.primary = primary
        self.fallback = fallback
    }

    public func verdict(for c: Candidate) async -> Verdict {
        if let v = try? await primary.verdict(for: c) { return v }
        return await fallback.verdict(for: c)
    }
}
