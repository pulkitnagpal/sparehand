import Foundation

/// One completed file move, kept so it can be undone.
public struct JournalEntry: Codable, Sendable, Equatable {
    public var tapID: String
    public var move: FileMove
    public var at: Date
    public init(tapID: String, move: FileMove, at: Date) { self.tapID = tapID; self.move = move; self.at = at }
}

public struct MoveReport: Sendable, Equatable {
    public var moved: [FileMove]
    public var skipped: [URL]
    public init(moved: [FileMove] = [], skipped: [URL] = []) { self.moved = moved; self.skipped = skipped }
}

/// Moves files without ever overwriting, journals each completed move, and can put them back.
public struct FileMover: Sendable {
    let store: Store
    let fileManager: FileManager

    public init(store: Store, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    public func perform(_ moves: [FileMove], tapID: String) throws -> MoveReport {
        var report = MoveReport()
        for m in moves {
            guard fileManager.fileExists(atPath: m.from.path) else { report.skipped.append(m.from); continue }
            try fileManager.createDirectory(at: m.to.deletingLastPathComponent(), withIntermediateDirectories: true)
            let target = FileMover.freeURL(m.to, fileManager: fileManager)
            do { try fileManager.moveItem(at: m.from, to: target) } catch { report.skipped.append(m.from); continue }
            let done = FileMove(from: m.from, to: target)
            try store.appendJournal(JournalEntry(tapID: tapID, move: done, at: Date()))
            report.moved.append(done)
        }
        return report
    }

    /// Moves everything back, newest first. Undoing twice does nothing the second time.
    public func undo(tapID: String) throws -> MoveReport {
        let undoID = "undo:" + tapID
        guard try store.journal(tapID: undoID).isEmpty else { return MoveReport() }
        var report = MoveReport()
        for e in try store.journal(tapID: tapID).reversed() {
            guard fileManager.fileExists(atPath: e.move.to.path) else { report.skipped.append(e.move.to); continue }
            try fileManager.createDirectory(at: e.move.from.deletingLastPathComponent(), withIntermediateDirectories: true)
            let back = FileMover.freeURL(e.move.from, fileManager: fileManager)
            do { try fileManager.moveItem(at: e.move.to, to: back) } catch { report.skipped.append(e.move.to); continue }
            let done = FileMove(from: e.move.to, to: back)
            try store.appendJournal(JournalEntry(tapID: undoID, move: done, at: Date()))
            report.moved.append(done)
        }
        return report
    }

    /// The URL itself if free, else "name (2).ext", "name (3).ext", …
    public static func freeURL(_ url: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent(), ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
