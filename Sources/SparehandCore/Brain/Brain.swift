import Foundation

public protocol HTTPTransport: Sendable {
    func post(_ url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> Data
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func post(_ url: URL, headers: [String: String], body: Data, timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BrainError.http((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }
}

public enum BrainError: Error { case http(Int, String), unparseable, unavailable(String) }

/// Pull the first {...} object out of a model's reply.
public func firstJSONObject(_ text: String) -> JSONValue? {
    guard let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}"), s < e,
          let obj = try? JSONSerialization.jsonObject(with: Data(text[s...e].utf8)) else { return nil }
    return JSONValue(any: obj)
}

// MARK: - Local model (Qwen on this Mac, OpenAI-compatible mlx_lm.server)

public struct LocalModel: Sendable {
    public var endpoint: URL
    public var model: String
    let transport: HTTPTransport

    public init(endpoint: URL = URL(string: "http://127.0.0.1:8765/v1/chat/completions")!,
                model: String = "mlx-community/Qwen3.5-4B-MLX-4bit", transport: HTTPTransport = URLSessionTransport()) {
        self.endpoint = endpoint; self.model = model; self.transport = transport
    }

    public func chat(system: String, user: String, maxTokens: Int = 120, timeout: TimeInterval = 60) async throws -> String {
        let body: [String: Any] = ["model": model, "temperature": 0.0, "max_tokens": maxTokens, "chat_template_kwargs": ["enable_thinking": false],
                                   "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        let data = try await transport.post(endpoint, headers: [:], body: try JSONSerialization.data(withJSONObject: body), timeout: timeout)
        guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = ((reply["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]),
              let content = msg["content"] as? String else { throw BrainError.unparseable }
        return content
    }

    public static let screenPrompt = """
        You are the first filter of a Mac assistant. You see a snapshot of what the Mac's sensors observed.
        Your only job: decide whether a smarter assistant should take a closer look. Say yes if there is ANY chance of something worth offering:
        wasted disk space or memory, clutter, old or duplicate files, leftover installers, something idle using resources, many tabs on one topic,
        a repeated routine, an upcoming moment, errors repeating, anything waiting on the user. Say no only when the snapshot is clearly ordinary.
        When unsure, say yes. Answer ONLY JSON: {"look_closer": true|false, "what": "<=10 words"}
        """

    /// High-recall filter: true means "send this to Claude". Unparseable answers count as yes.
    public func screen(_ snapshot: Snapshot) async throws -> (lookCloser: Bool, what: String) {
        let out = try await chat(system: Self.screenPrompt, user: "Snapshot:\n" + snapshot.text, maxTokens: 60)
        guard let v = firstJSONObject(out) else { return (true, "unparseable") }
        return (v["look_closer"]?.bool ?? true, v["what"]?.string ?? "")
    }

    /// Picks one of `options` for a file from its text. Falls back to the last option.
    public func classify(text: String, into options: [String]) async throws -> String {
        let system = """
            Pick the folder that best fits one screenshot, from its on-screen text. Folders: \(options.map { "\"\($0)\"" }.joined(separator: ", ")).
            If the text is empty or fits none, pick "\(options.last ?? "Other")". Answer ONLY JSON: {"folder": "<one of the folders>"}
            """
        let out = try await chat(system: system, user: text.isEmpty ? "(no text)" : text, maxTokens: 30, timeout: 30)
        let pick = firstJSONObject(out)?["folder"]?.string?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return options.first { $0.lowercased() == pick } ?? options.first { pick.contains($0.lowercased()) } ?? (options.last ?? "Other")
    }

    public func isUp() async -> Bool { (try? await chat(system: "Reply OK.", user: "ping", maxTokens: 3, timeout: 5)) != nil }
}

// MARK: - Claude

public struct ClaudeReply: Sendable { public var text: String; public var costUSD: Double }

public protocol ClaudeBackend: Sendable {
    var label: String { get }
    func complete(system: String, user: String) async throws -> ClaudeReply
}

public enum Keychain {
    /// Reads a generic password with /usr/bin/security (whose access the item was created with). Never logged.
    public static func read(_ service: String) -> String? {
        let s = Shell.run("/usr/bin/security", ["find-generic-password", "-s", service, "-w"], timeout: 10).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
    public static let apiKeyService = "sparehand.anthropic-key"
    public static let oauthService = "sparehand.claude-oauth"
}

/// The user's own Anthropic API key, over the Messages API.
public struct ClaudeAPI: ClaudeBackend {
    public var label: String { "Claude API" }
    let key: String
    let model: String
    let transport: HTTPTransport
    public init(key: String, model: String = "claude-sonnet-5-5", transport: HTTPTransport = URLSessionTransport()) {
        self.key = key; self.model = model; self.transport = transport
    }

    public func complete(system: String, user: String) async throws -> ClaudeReply {
        let body: [String: Any] = ["model": model, "max_tokens": 1500, "system": system, "messages": [["role": "user", "content": user]]]
        let data = try await transport.post(URL(string: "https://api.anthropic.com/v1/messages")!,
                                            headers: ["x-api-key": key, "anthropic-version": "2023-06-01"],
                                            body: try JSONSerialization.data(withJSONObject: body), timeout: 120)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BrainError.unparseable }
        let text = ((obj["content"] as? [[String: Any]]) ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        let usage = obj["usage"] as? [String: Any]
        let cost = Double((usage?["input_tokens"] as? Int) ?? 0) * 2e-6 + Double((usage?["output_tokens"] as? Int) ?? 0) * 10e-6
        return ClaudeReply(text: text, costUSD: cost)
    }
}

/// Headless Claude Code with a subscription token, in its own config folder. For development and demos.
public struct ClaudeCLI: ClaudeBackend {
    public var label: String { "Claude (CLI)" }
    let token: String
    let model: String
    public init(token: String, model: String = "claude-sonnet-5-5") { self.token = token; self.model = model }

    public func complete(system: String, user: String) async throws -> ClaudeReply {
        guard let claude = Shell.which("claude") else { throw BrainError.unavailable("Claude Code isn't installed") }
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CONFIG_DIR"] = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sparehand-claude").path
        env["CLAUDE_CODE_OAUTH_TOKEN"] = token
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        let args = ["-p", "--tools", "", "--no-session-persistence", "--setting-sources", "", "--model", model,
                    "--system-prompt", system, "--output-format", "json", user]
        let model = self.model
        let out = await Task.detached { Shell.run(claude, args, env: env, cwd: "/private/tmp", timeout: 240) }.value
        guard let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] else {
            throw BrainError.unavailable("No answer from \(model)")
        }
        if obj["is_error"] as? Bool == true { throw BrainError.unavailable(obj["result"] as? String ?? "Claude error") }
        return ClaudeReply(text: obj["result"] as? String ?? "", costUSD: obj["total_cost_usd"] as? Double ?? 0)
    }
}

public enum Claude {
    /// The user's API key if there is one, else the subscription token (development and demos), else nothing.
    public static func fromKeychain() -> ClaudeBackend? {
        if let key = Keychain.read(Keychain.apiKeyService) { return ClaudeAPI(key: key) }
        if let token = Keychain.read(Keychain.oauthService) { return ClaudeCLI(token: token) }
        return nil
    }
}

// MARK: - The gate: Claude decides what (if anything) to offer

public struct Proposal: Sendable, Equatable {
    public var steps: [ToolCall]
    public var title: String
    public var body: String
    public var why: String
    public var actionLabel: String
    public var repeatTitle: String?
    public var confidence: Int
}

public enum Gate {
    public static func system(memory: [String]) -> String {
        """
        You are the noticing step of Sparehand, a proactive assistant on the user's Mac. You see a snapshot of what the Mac's sensors observed.
        Decide if there is ONE concrete, helpful thing to offer that the user would very likely approve right now, and plan it with the tools below.
        Offer when: something is wasting space or resources, something is waiting on the user, a repeated manual routine could be one tap, \
        an upcoming moment needs preparing, scattered work could be pulled together, \
        or a work session is ending and open work could be saved and put away so it is easy to pick up later.
        Stay silent when: nothing is wrong, the thing is in active use, the user is presenting or sharing the screen, the timing is bad, \
        or the benefit is small. Silence is the most common correct answer.
        Never invent facts that are not in the snapshot. Do not repeat an earlier offer unless something important changed. \
        Sparehand does every step on this Mac after the user taps, and each step can be undone.

        \(Tools.catalogue)

        What you know about this user:
        \(memory.isEmpty ? "- nothing yet" : memory.map { "- " + $0 }.joined(separator: "\n"))

        Answer ONLY JSON:
        {"propose": true|false, "steps": [{"tool": "...", "args": {...}}], "card_title": "<=8 words", \
        "card_body": "<=30 words: exactly what will happen", "why_noticed": "<=20 words: what in the snapshot made you notice", \
        "action_label": "<=3 words", "repeat_title": "<=8 words, the title to use if this comes back, with {count} for the number of new items", \
        "confidence": 1-5}
        """
    }

    public static func user(_ snapshot: Snapshot, earlier: [String]) -> String {
        "Earlier offers today: \(earlier.isEmpty ? "none" : earlier.joined(separator: "; "))\nSnapshot:\n" + snapshot.text
    }

    /// nil when Claude stays silent or the answer can't be read.
    public static func parse(_ text: String) -> Proposal? {
        guard let v = firstJSONObject(text), v["propose"]?.bool == true else { return nil }
        let steps = (v["steps"]?.array ?? []).compactMap { s -> ToolCall? in
            guard let t = s["tool"]?.string else { return nil }
            return ToolCall(tool: t, args: s["args"] ?? .object([:]))
        }
        return Proposal(steps: steps, title: v["card_title"]?.string ?? "", body: v["card_body"]?.string ?? "",
                        why: v["why_noticed"]?.string ?? "", actionLabel: v["action_label"]?.string ?? "Do it",
                        repeatTitle: v["repeat_title"]?.string, confidence: Int(v["confidence"]?.number ?? 0))
    }
}

// MARK: - Validation: nothing invented gets through

public enum Validator {
    public struct Checked: Sendable { public var targets: [String]; public var evidence: [EvidenceItem] }

    public static func check(_ p: Proposal, snapshot: Snapshot, env: Environment) -> Result<Checked, ValidationFailure> {
        guard (1...5).contains(p.steps.count) else { return .failure(.init("no steps")) }
        guard !p.title.isEmpty, !p.body.isEmpty else { return .failure(.init("empty card")) }
        guard p.confidence >= 3 else { return .failure(.init("confidence \(p.confidence)")) }
        let copy = (p.title + " " + p.body + " " + p.actionLabel).lowercased()
        if ["permanently", "erase", "wipe"].contains(where: copy.contains) { return .failure(.init("copy claims a permanent deletion")) }
        let binning = p.steps.contains { $0.tool == "move_to_bin" }
        if !binning, ["delete", "trash", " bin"].contains(where: copy.contains) { return .failure(.init("copy says delete but the plan doesn't")) }

        var targets: [String] = [], evidence: [EvidenceItem] = []
        let snapTabs = Set(snapshot.tabs.map { Redactor.url($0.url.absoluteString) })
        for s in p.steps {
            guard Tools.spec(s.tool) != nil else { return .failure(.init("unknown tool \(s.tool)")) }
            switch s.tool {
            case "sort_by_content", "organize_files", "move_to_bin":
                guard let sel = FileSelector(s.args["files"]) else { return .failure(.init("\(s.tool): no file selector")) }
                let files = sel.resolve(home: env.home, now: env.now())
                guard !files.isEmpty else { return .failure(.init("\(s.tool): selector matches nothing")) }
                if s.tool != "move_to_bin", Tools.folderURL(s.args["into"]?.string ?? "~/Pictures/Screenshots", home: env.home) == nil {
                    return .failure(.init("\(s.tool): destination outside home"))
                }
                if s.tool == "sort_by_content", (s.args["folders"]?.strings ?? []).isEmpty { return .failure(.init("sort_by_content: no folders")) }
                targets += files.map(\.lastPathComponent)
                evidence.append(EvidenceItem(label: "\(files.count) files in \(sel.folder)", detail: files.first.map(\.lastPathComponent) ?? ""))
            case "close_tabs":
                let urls = s.args["urls"]?.strings.map(Redactor.url) ?? []
                guard !urls.isEmpty, urls.allSatisfy(snapTabs.contains) else { return .failure(.init("close_tabs: tab not open")) }
                targets += urls
                evidence.append(EvidenceItem(label: "\(urls.count) tabs", detail: urls.first ?? ""))
            case "stop_container":
                let names = s.args["names"]?.strings ?? []
                guard !names.isEmpty, names.allSatisfy(snapshot.containers.contains) else { return .failure(.init("stop_container: not running")) }
                targets += names
            case "quit_app":
                guard let n = s.args["name"]?.string, snapshot.runningApps.contains(n) else { return .failure(.init("quit_app: not running")) }
                targets.append(n)
            case "create_note":
                guard !(s.args["title"]?.string ?? "").isEmpty else { return .failure(.init("create_note: no title")) }
                targets.append("note:" + (s.args["title"]?.string ?? ""))
            default:
                targets.append(s.tool)
            }
        }
        return .success(Checked(targets: targets, evidence: evidence))
    }
}

public struct ValidationFailure: Error, Sendable, Equatable {
    public var reason: String
    init(_ r: String) { reason = r }
}

// MARK: - Learned skills: an approved Claude plan that Sparehand can repeat on this Mac

public struct Skill: Codable, Sendable, Equatable {
    public var id: String
    public var steps: [ToolCall]
    public var titleTemplate: String
    public var body: String
    public var why: String
    public var actionLabel: String
    public var learnedAt: Date
    public var minCount: Int
}

public enum Skills {
    static let fileTools: Set<String> = ["sort_by_content", "organize_files", "move_to_bin"]

    public static func all(_ store: Store) -> [Skill] {
        guard let s = try? store.setting("skills") else { return [] }
        return (try? JSONDecoder().decode([Skill].self, from: Data(s.utf8))) ?? []
    }

    static func save(_ skills: [Skill], _ store: Store) throws {
        try store.setSetting("skills", String(decoding: try JSONEncoder().encode(skills), as: UTF8.self))
    }

    /// Learns from an approved Claude offer whose steps pick files by selector. Explicit file names are dropped
    /// from the selector, so the skill matches new files of the same kind.
    @discardableResult
    public static func learn(from tap: Tap, store: Store, now: Date) throws -> Skill? {
        guard tap.candidate.origin == .claude, tap.candidate.steps.allSatisfy({ fileTools.contains($0.tool) }) else { return nil }
        let steps = tap.candidate.steps.map { s -> ToolCall in
            guard case .object(var args) = s.args, case .object(var files)? = args["files"] else { return s }
            files.removeValue(forKey: "names"); files.removeValue(forKey: "older_than_days")
            args["files"] = .object(files)
            return ToolCall(tool: s.tool, args: .object(args))
        }
        let id = Fingerprint.make("skill", steps.map { "\($0.tool):\(String(decoding: (try? JSONEncoder().encode($0.args)) ?? Data(), as: UTF8.self))" })
        var list = all(store)
        guard !list.contains(where: { $0.id == id }) else { return nil }
        let title = tap.candidate.repeatTitle ?? tap.verdict.title.replacingOccurrences(of: #"\d+"#, with: "{count}", options: .regularExpression)
        let skill = Skill(id: id, steps: steps, titleTemplate: title, body: tap.verdict.body, why: tap.candidate.why,
                          actionLabel: tap.verdict.actionLabel, learnedAt: now, minCount: 5)
        list.append(skill)
        try save(list, store)
        return skill
    }

    /// Offers from learned skills whose files are back (at least `minCount` of them). Runs fully on this Mac.
    public static func offers(env: Environment, now: Date) -> [Candidate] {
        all(env.store).compactMap { skill in
            guard let first = skill.steps.first, let sel = FileSelector(first.args["files"]) else { return nil }
            let files = sel.resolve(home: env.home, now: now)
            guard files.count >= skill.minCount else { return nil }
            let n = "\(files.count)"
            let id = Fingerprint.make("skill:" + skill.id, files.map(\.lastPathComponent))
            return Candidate(id: id, origin: .skill, why: "You approved this before, and \(n) new matching files are back in \(sel.folder).",
                             evidence: [EvidenceItem(label: "\(n) files in \(sel.folder)", detail: files.first?.lastPathComponent ?? "")],
                             steps: skill.steps, noticedAt: now, skillID: skill.id,
                             repeatTitle: skill.titleTemplate.replacingOccurrences(of: "{count}", with: n))
        }
    }
}
