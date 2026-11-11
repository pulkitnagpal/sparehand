import Foundation

/// The card's words.
public struct Verdict: Codable, Sendable, Equatable {
    public var title: String
    public var body: String
    public var actionLabel: String
    public var confidence: Int

    public init(title: String, body: String, actionLabel: String, confidence: Int) {
        self.title = title; self.body = body; self.actionLabel = actionLabel; self.confidence = confidence
    }
}

public enum TapState: String, Codable, Sendable {
    case pending, approved, running, done, failed, dismissed, never, undone
}

/// A suggestion shown to the user, and what became of it.
public struct Tap: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var candidate: Candidate
    public var verdict: Verdict
    public var state: TapState
    public var createdAt: Date
    public var finishedAt: Date?
    /// Result or failure text shown in the feed ("Sorted 25 into 5 folders").
    public var note: String?
    /// Something the action created, used by undo (for example a note's id).
    public var resultRef: String?

    public init(candidate: Candidate, verdict: Verdict, state: TapState = .pending, createdAt: Date,
                finishedAt: Date? = nil, note: String? = nil, resultRef: String? = nil) {
        self.id = candidate.id; self.candidate = candidate; self.verdict = verdict; self.state = state
        self.createdAt = createdAt; self.finishedAt = finishedAt; self.note = note; self.resultRef = resultRef
    }
}
