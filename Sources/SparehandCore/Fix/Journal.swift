import Foundation

/// One completed file move, kept so it can be undone.
public struct JournalEntry: Codable, Sendable, Equatable {
    public var tapID: String
    public var move: FileMove
    public var at: Date
    public init(tapID: String, move: FileMove, at: Date) { self.tapID = tapID; self.move = move; self.at = at }
}
