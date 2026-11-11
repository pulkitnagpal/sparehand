import CryptoKit
import Foundation

/// Who came up with an offer: Claude looking at a new situation, or a skill Sparehand learned and runs on this Mac.
public enum Origin: String, Codable, Sendable, CaseIterable {
    case claude, skill
}

/// One line of proof shown on a tap card ("Screenshot 2026-02-03.png" / "4 months old").
public struct EvidenceItem: Codable, Sendable, Equatable {
    public var label: String
    public var detail: String
    public init(label: String, detail: String) { self.label = label; self.detail = detail }
}

public struct FileMove: Codable, Sendable, Equatable {
    public var from: URL
    public var to: URL
    public init(from: URL, to: URL) { self.from = from; self.to = to }
}

public struct Tab: Codable, Sendable, Equatable, Hashable {
    public var browser: String
    public var title: String
    public var url: URL
    public init(browser: String, title: String, url: URL) { self.browser = browser; self.title = title; self.url = url }
}

/// An offer: the steps Sparehand will run if the user approves, and why it was noticed.
public struct Candidate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var origin: Origin
    /// "Why I noticed": one plain sentence.
    public var why: String
    public var evidence: [EvidenceItem]
    public var steps: [ToolCall]
    public var noticedAt: Date
    /// The skill this offer came from (origin .skill).
    public var skillID: String?
    /// The card title to use when this offer repeats, with "{count}" for the new item count.
    public var repeatTitle: String?

    public init(id: String, origin: Origin, why: String, evidence: [EvidenceItem] = [], steps: [ToolCall], noticedAt: Date,
                skillID: String? = nil, repeatTitle: String? = nil) {
        self.id = id; self.origin = origin; self.why = why; self.evidence = evidence; self.steps = steps
        self.noticedAt = noticedAt; self.skillID = skillID; self.repeatTitle = repeatTitle
    }

    /// Every step can be undone.
    public var isReversible: Bool { steps.allSatisfy { Tools.spec($0.tool)?.reversible ?? false } }
}

/// A stable id from what an offer would touch: the same tool on the same targets gives the same id.
public enum Fingerprint {
    public static func make(_ kind: String, _ keys: [String]) -> String {
        let text = ([kind] + keys.sorted()).joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
