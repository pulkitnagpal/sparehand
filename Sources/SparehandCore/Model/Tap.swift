import Foundation

/// The judge's answer for a candidate: whether to show it and the card's words.
public struct Verdict: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable { case model, rules }
    public var show: Bool
    public var value: Int
    public var title: String
    public var body: String
    public var actionLabel: String
    public var source: Source

    public init(show: Bool, value: Int, title: String, body: String, actionLabel: String, source: Source) {
        self.show = show; self.value = value; self.title = title; self.body = body
        self.actionLabel = actionLabel; self.source = source
    }
}

public enum TapState: String, Codable, Sendable {
    case pending, approved, running, done, failed, dismissed, undone
}

/// A suggestion shown to the user, and what became of it.
public struct Tap: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var candidate: Candidate
    public var verdict: Verdict
    public var state: TapState
    public var createdAt: Date
    public var finishedAt: Date?
    /// Failure text shown in the feed.
    public var note: String?
    /// Something the action created, used by undo (for example the note's id).
    public var resultRef: String?

    public init(candidate: Candidate, verdict: Verdict, state: TapState = .pending, createdAt: Date,
                finishedAt: Date? = nil, note: String? = nil, resultRef: String? = nil) {
        self.id = candidate.id; self.candidate = candidate; self.verdict = verdict; self.state = state
        self.createdAt = createdAt; self.finishedAt = finishedAt; self.note = note; self.resultRef = resultRef
    }
}
