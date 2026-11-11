import Foundation

/// True while the user shouldn't be interrupted (full-screen app, a call). The app supplies it.
public protocol QuietRules: Sendable {
    func isQuiet() -> Bool
}

/// Runs the watchable "tabs → note" job. The app's runner uses Sparehand's own screen; the CLI's is headless.
public protocol JobRunner: Sendable {
    /// Returns the created note's id.
    func runTabsToNote(tap: Tap) async throws -> String
}

/// Runs the watchers, asks the judge, keeps taps polite (no repeats, gaps between them, quiet times) and
/// carries out what the user approves.
public actor Engine {
    let env: Environment
    let watchers: [any Watcher]
    let judge: any Judge
    let quiet: any QuietRules
    let jobs: any JobRunner
    let minGap: TimeInterval

    public init(env: Environment, watchers: [any Watcher], judge: any Judge, quiet: any QuietRules, jobs: any JobRunner,
                minGap: TimeInterval = 600) {
        self.env = env; self.watchers = watchers; self.judge = judge; self.quiet = quiet; self.jobs = jobs; self.minGap = minGap
    }

    var store: Store { env.store }

    /// New pending taps to show now (taps made while it's quiet go to the feed only).
    public func tick() async -> [Tap] {
        var fresh: [Tap] = []
        let now = env.now()
        for watcher in watchers {
            guard let candidates = try? await watcher.candidates(env) else { continue }
            for c in candidates {
                if let existing = try? store.tap(id: c.id) {
                    guard existing.state == .dismissed, let until = snoozedUntil(c.id), until <= now else { continue }
                } else if let last = try? store.lastShown(watcher: c.watcher), now.timeIntervalSince(last) < minGap {
                    continue
                }
                let v = await judge.verdict(for: c)
                let tap = Tap(candidate: c, verdict: v, state: v.show ? .pending : .dismissed, createdAt: now)
                try? store.upsert(tap)
                if !v.show { try? store.setSetting("snooze.\(c.id)", "\(Date.distantFuture.timeIntervalSince1970)") }
                if v.show { fresh.append(tap) }
            }
        }
        return quiet.isQuiet() ? [] : fresh
    }

    public func approve(_ tapID: String) async -> Tap {
        guard var tap = try? store.tap(id: tapID) else { return missing(tapID) }
        tap.state = .running
        try? store.upsert(tap)
        do {
            switch tap.candidate.plan {
            case .moveFiles(let moves):
                let report = try FileMover(store: store).perform(moves, tapID: tap.id)
                if report.moved.isEmpty && !moves.isEmpty { throw EngineError.nothingMoved }
                if !report.skipped.isEmpty { tap.note = "\(report.skipped.count) files had already moved." }
            case .deletePermanently(let urls):
                var failed: [String] = []
                for url in urls {
                    do { try FileManager.default.removeItem(at: url) } catch { failed.append(url.lastPathComponent) }
                }
                if failed.count == urls.count && !urls.isEmpty { throw EngineError.deleteFailed(failed) }
                if !failed.isEmpty { tap.note = "Couldn't delete: " + failed.joined(separator: ", ") }
            case .tabsToNote:
                tap.resultRef = try await jobs.runTabsToNote(tap: tap)
            }
            tap.state = .done
        } catch {
            tap.state = .failed
            tap.note = Self.describe(error)
        }
        tap.finishedAt = env.now()
        try? store.upsert(tap)
        return tap
    }

    public func dismiss(_ tapID: String, snooze: TimeInterval = 86_400) async {
        guard var tap = try? store.tap(id: tapID) else { return }
        tap.state = .dismissed
        try? store.upsert(tap)
        try? store.setSetting("snooze.\(tapID)", "\(env.now().addingTimeInterval(snooze).timeIntervalSince1970)")
    }

    public func undo(_ tapID: String) async -> Tap {
        guard var tap = try? store.tap(id: tapID), tap.state == .done else { return (try? store.tap(id: tapID)) ?? missing(tapID) }
        do {
            switch tap.candidate.plan {
            case .moveFiles:
                let report = try FileMover(store: store).undo(tapID: tap.id)
                if !report.skipped.isEmpty { tap.note = "\(report.skipped.count) files couldn't be put back." }
            case .tabsToNote:
                if let note = tap.resultRef { try await NotesWriter(runner: env.scripts).delete(noteID: note) }
            case .deletePermanently:
                return tap
            }
            tap.state = .undone
        } catch {
            tap.note = "Undo failed: " + Self.describe(error)
        }
        try? store.upsert(tap)
        return tap
    }

    /// What the menu-bar feed shows: waiting taps, and what was done in the last day.
    public func feed() async -> (pending: [Tap], done: [Tap]) {
        let pending = (try? store.taps(states: [.pending])) ?? []
        let dayAgo = env.now().addingTimeInterval(-86_400)
        let done = ((try? store.taps(states: [.done, .failed, .undone, .running])) ?? []).filter { ($0.finishedAt ?? $0.createdAt) >= dayAgo }
        return (pending, done)
    }

    public func tap(_ id: String) async -> Tap? { try? store.tap(id: id) }

    // MARK: -

    enum EngineError: Error { case nothingMoved, deleteFailed([String]) }

    static func describe(_ error: Error) -> String {
        switch error {
        case EngineError.nothingMoved: return "The files were no longer there."
        case EngineError.deleteFailed(let names): return "Couldn't delete \(names.joined(separator: ", "))."
        case ClaudeJobError.notInstalled: return "Claude Code isn't installed."
        case ClaudeJobError.noTable: return "Claude didn't return a table."
        case ClaudeJobError.failed(let m): return m
        case let e as ScriptError: return e.message
        default: return "\(error)"
        }
    }

    func snoozedUntil(_ id: String) -> Date? {
        (try? store.setting("snooze.\(id)")).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    func missing(_ id: String) -> Tap {
        let c = Candidate(id: id, watcher: .screenshots, summary: "", evidence: [], plan: .moveFiles([]), noticedAt: env.now())
        return Tap(candidate: c, verdict: Verdict(show: false, value: 0, title: "", body: "", actionLabel: "", source: .rules),
                   state: .failed, createdAt: env.now(), note: "That suggestion no longer exists.")
    }
}
