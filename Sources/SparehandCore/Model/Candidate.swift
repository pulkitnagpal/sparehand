import CryptoKit
import Foundation

/// The kinds of thing Sparehand watches in milestone 1.
public enum WatcherID: String, Codable, Sendable, CaseIterable {
    case screenshots, bin, tabs
}

/// One line of proof shown on a tap card ("Xcode_26.dmg" / "6.2 GB").
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

/// What Sparehand will do if the user approves.
public enum ActionPlan: Codable, Sendable, Equatable {
    case moveFiles([FileMove])
    case deletePermanently([URL])
    case tabsToNote(topic: String, tabs: [Tab])

    /// Undo exists for moves (move back) and notes (delete the note); permanent deletion has none.
    public var isReversible: Bool {
        if case .deletePermanently = self { return false }
        return true
    }
}

/// Something a watcher noticed. Numbers are already computed in code; the judge only decides and words it.
public struct Candidate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var watcher: WatcherID
    public var summary: String
    public var facts: [String: String]
    public var evidence: [EvidenceItem]
    public var plan: ActionPlan
    public var noticedAt: Date

    public init(id: String, watcher: WatcherID, summary: String, facts: [String: String] = [:],
                evidence: [EvidenceItem], plan: ActionPlan, noticedAt: Date) {
        self.id = id; self.watcher = watcher; self.summary = summary; self.facts = facts
        self.evidence = evidence; self.plan = plan; self.noticedAt = noticedAt
    }
}

/// A stable id for a candidate: the same files or tabs give the same id, whatever order they were found in.
public enum Fingerprint {
    public static func make(_ watcher: WatcherID, _ keys: [String]) -> String {
        let text = ([watcher.rawValue] + keys.sorted()).joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
