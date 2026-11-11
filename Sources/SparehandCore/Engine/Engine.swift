import Foundation

/// True while the user shouldn't be interrupted (full-screen app, a call). The app supplies it.
public protocol QuietRules: Sendable {
    func isQuiet() -> Bool
}

public struct NeverQuiet: QuietRules { public init() {}; public func isQuiet() -> Bool { false } }

public struct Limits: Sendable {
    public var perHour = 3
    public var perDay = 12
    public var idleSeconds: Double = 300
    public init() {}
}

/// What one look decided, for the log and the CLI.
public struct LookResult: Sendable {
    public var taps: [Tap] = []
    public var steps: [String] = []
    public var claudeCostUSD: Double = 0
}

/// The decision ladder. Each rung can end it, cheapest first:
/// policy (code) → learned skills (this Mac) → screen (Qwen, this Mac) → Claude → validation (code) → card.
public actor Engine {
    let env: Environment
    let senses: Senses
    let local: LocalModel?
    let claude: ClaudeBackend?
    let quiet: any QuietRules
    let limits: Limits

    public init(env: Environment, senses: Senses, local: LocalModel?, claude: ClaudeBackend?, quiet: any QuietRules, limits: Limits = Limits()) {
        self.env = env; self.senses = senses; self.local = local; self.claude = claude; self.quiet = quiet; self.limits = limits
    }

    var store: Store { env.store }

    public func sample() async { await senses.sample() }

    /// Looks at the Mac once. `force` skips the quiet, idle, limit and nothing-changed checks (the "Look now" shortcut).
    public func look(force: Bool = false) async -> LookResult {
        var r = LookResult()
        let snap = await senses.snapshot()
        let now = env.now()
        var log: [String: Any] = ["time": now.timeIntervalSince1970, "force": force]
        defer { log["steps"] = r.steps; Self.appendLog(log) }

        if !force {
            if quiet.isQuiet() || snap.fullscreen { r.steps.append("quiet: full screen or a call"); return r }
            if snap.idleSeconds > limits.idleSeconds { r.steps.append("quiet: you're away"); return r }
            let recent = (try? store.taps(since: now.addingTimeInterval(-86_400))) ?? []
            if recent.filter({ $0.createdAt > now.addingTimeInterval(-3600) }).count >= limits.perHour || recent.count >= limits.perDay {
                r.steps.append("quiet: card limit reached"); return r
            }
        }

        let maxCards = 3
        var claimed = Set<String>()   // targets already covered by a card in this look

        // 1. Learned skills: no cloud at all.
        for c in Skills.offers(env: env, now: now) where r.taps.count < maxCards {
            guard isNew(c.id, now: now) else { continue }
            guard case .success(let checked) = Validator.check(Proposal(steps: c.steps, title: c.repeatTitle ?? "", body: "x", why: c.why,
                                                                        actionLabel: "x", repeatTitle: nil, confidence: 5), snapshot: snap, env: env) else { continue }
            var cand = c
            cand.evidence = checked.evidence
            cand.benefit = checked.measured
            let skill = Skills.all(store).first { $0.id == c.skillID }
            let tap = Tap(candidate: cand, verdict: Verdict(title: c.repeatTitle ?? "Same as last time", body: skill?.body ?? "",
                                                            actionLabel: skill?.actionLabel ?? "Do it", confidence: 5), createdAt: now)
            try? store.upsert(tap)
            r.taps.append(tap)
            claimed.formUnion(checked.targets)
            r.steps.append("skill matched on this Mac: \(tap.verdict.title)")
            log["skill"] = c.skillID
        }

        // 2. Nothing salient changed since Claude last looked: stop.
        let lastKey = try? store.setting("last.salient")
        if !force, lastKey == snap.salientKey { r.steps.append("nothing changed since the last look"); return r }
        guard r.taps.count < maxCards else { return r }

        // 3. Local screen.
        if let local {
            do {
                let s = try await local.screen(snap)
                r.steps.append("Qwen screen: \(s.lookCloser ? "look closer" : "nothing here") (\(s.what))")
                log["screen"] = ["look_closer": s.lookCloser, "what": s.what]
                if !s.lookCloser { try? store.setSetting("last.salient", snap.salientKey); return r }
            } catch {
                r.steps.append("Qwen unavailable, asking Claude")
            }
        }

        // 4. Claude decides: up to 3 offers, best first.
        guard let claude else { r.steps.append("no Claude connected: only learned skills run"); return r }
        let earlier = ((try? store.taps(since: Calendar.current.startOfDay(for: now))) ?? []).map(\.verdict.title)
        let reply: ClaudeReply
        do { reply = try await claude.complete(system: Gate.system(memory: memory()), user: Gate.user(snap, earlier: earlier)) }
        catch { r.steps.append("Claude failed: \(error)"); return r }
        try? store.setSetting("last.salient", snap.salientKey)
        r.claudeCostUSD = reply.costUSD
        log["claude"] = ["text": reply.text, "cost": reply.costUSD, "backend": claude.label]
        Self.saveSnapshot(snap, at: now)
        let proposals = Gate.parseAll(reply.text)
        if proposals.isEmpty { r.steps.append("Claude: nothing worth offering"); return r }

        // 5. Validate and dedupe each.
        var rejected: [String] = []
        for p in proposals where r.taps.count < maxCards {
            r.steps.append("Claude: \(p.title) [\(p.steps.map(\.tool).joined(separator: ", "))] confidence \(p.confidence)")
            switch Validator.check(p, snapshot: snap, env: env) {
            case .failure(let f):
                r.steps.append("  rejected: \(f.reason)"); rejected.append(f.reason)
            case .success(let checked):
                if !claimed.isDisjoint(with: checked.targets) { r.steps.append("  skipped: overlaps another card"); continue }
                let id = Fingerprint.make(p.steps.map(\.tool).joined(separator: "+"), checked.targets)
                guard isNew(id, now: now) else { r.steps.append("  already offered"); continue }
                var cand = Candidate(id: id, origin: .claude, why: p.why, evidence: checked.evidence, steps: p.steps, noticedAt: now, repeatTitle: p.repeatTitle)
                cand.benefit = checked.measured ?? p.benefit
                let tap = Tap(candidate: cand, verdict: Verdict(title: p.title, body: p.body, actionLabel: p.actionLabel, confidence: p.confidence), createdAt: now)
                try? store.upsert(tap)
                r.taps.append(tap)
                claimed.formUnion(checked.targets)
            }
        }
        if !rejected.isEmpty { log["rejected"] = rejected }
        return r
    }

    /// Offered before? Pending or done within a day, "Not now" within a week, or "Never".
    func isNew(_ id: String, now: Date) -> Bool {
        guard let t = try? store.tap(id: id) else { return true }
        switch t.state {
        case .never: return false
        case .dismissed: return now.timeIntervalSince(t.finishedAt ?? t.createdAt) > 7 * 86_400
        case .undone, .failed: return now.timeIntervalSince(t.createdAt) > 86_400
        default: return now.timeIntervalSince(t.createdAt) > 86_400
        }
    }

    // MARK: - acting

    public func approve(_ id: String, progress: @escaping @Sendable (String) -> Void = { _ in }) async -> Tap? {
        guard var tap = try? store.tap(id: id) else { return nil }
        tap.state = .running
        try? store.upsert(tap)
        var lines: [String] = []
        do {
            for step in tap.candidate.steps {
                lines.append(try await Tools.run(step, tapID: tap.id, ctx: ToolContext(env: env, local: local, progress: progress)))
            }
            tap.state = .done
            tap.note = lines.filter { !$0.isEmpty }.joined(separator: " · ")
            if (try? Skills.learn(from: tap, store: store, now: env.now())) ?? nil != nil { tap.note! += " · Learned" }
        } catch {
            tap.state = lines.isEmpty ? .failed : .done
            tap.note = (lines + [(error as? ToolError)?.message ?? "\(error)"]).joined(separator: " · ")
        }
        tap.finishedAt = env.now()
        try? store.upsert(tap)
        return tap
    }

    public func dismiss(_ id: String) {
        guard var tap = try? store.tap(id: id) else { return }
        tap.state = .dismissed; tap.finishedAt = env.now()
        try? store.upsert(tap)
    }

    /// "Never for this": the offer won't come back, and Claude is told.
    public func never(_ id: String) {
        guard var tap = try? store.tap(id: id) else { return }
        tap.state = .never; tap.finishedAt = env.now()
        try? store.upsert(tap)
        addMemory("Doesn't want this kind of offer: \(tap.verdict.title) (\(tap.candidate.steps.map(\.tool).joined(separator: ", ")))")
    }

    public func undo(_ id: String) async -> Tap? {
        guard var tap = try? store.tap(id: id), tap.state == .done else { return nil }
        do { tap.note = try await Tools.undo(tapID: id, env: env); tap.state = .undone }
        catch { tap.note = "Undo failed: \(error)" }
        try? store.upsert(tap)
        return tap
    }

    public func feed() -> (pending: [Tap], done: [Tap]) {
        let pending = (try? store.taps(states: [.pending])) ?? []
        let dayAgo = env.now().addingTimeInterval(-86_400)
        let done = ((try? store.taps(states: [.done, .failed, .undone, .running])) ?? []).filter { ($0.finishedAt ?? $0.createdAt) >= dayAgo }
        return (pending, done)
    }

    public func tap(_ id: String) -> Tap? { try? store.tap(id: id) }

    // MARK: - memory and logs

    public func memory() -> [String] {
        guard let s = try? store.setting("memory") else { return [] }
        return (try? JSONDecoder().decode([String].self, from: Data(s.utf8))) ?? []
    }

    public func addMemory(_ line: String) {
        var m = memory()
        guard !m.contains(line) else { return }
        m.append(line)
        try? store.setSetting("memory", String(decoding: (try? JSONEncoder().encode(Array(m.suffix(15)))) ?? Data(), as: UTF8.self))
    }

    /// Every decision, kept on this Mac: the training data for moving decisions local later.
    static func appendLog(_ entry: [String: Any]) {
        let url = Environment.supportDirectory.appendingPathComponent("decisions.jsonl")
        guard let data = try? JSONSerialization.data(withJSONObject: entry) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data + Data("\n".utf8)); try? h.close() }
        else { try? (data + Data("\n".utf8)).write(to: url) }
    }

    static func saveSnapshot(_ s: Snapshot, at: Date) {
        let dir = Environment.supportDirectory.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? s.json.write(to: dir.appendingPathComponent("\(Int(at.timeIntervalSince1970)).json"))
    }
}
