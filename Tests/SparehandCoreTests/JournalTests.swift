import Foundation
import Testing
@testable import SparehandCore

@Suite struct JournalTests {
    @Test func movesAndCreatesFolders() throws {
        let d = try TestDir(), s = try Store.inMemory()
        try d.file("Desktop/a.png", "A")
        let r = try FileMover(store: s).perform([FileMove(from: d.at("Desktop/a.png"), to: d.at("Pictures/2026-09/a.png"))], tapID: "t")
        #expect(r.moved.count == 1 && r.skipped.isEmpty)
        #expect(d.read("Pictures/2026-09/a.png") == "A")
        #expect(!d.exists("Desktop/a.png"))
    }

    @Test func suffixesOnCollision() throws {
        let d = try TestDir(), s = try Store.inMemory()
        try d.file("Desktop/a.png", "new")
        try d.file("Pictures/a.png", "old")
        let r = try FileMover(store: s).perform([FileMove(from: d.at("Desktop/a.png"), to: d.at("Pictures/a.png"))], tapID: "t")
        #expect(r.moved.first?.to.lastPathComponent == "a (2).png")
        #expect(d.read("Pictures/a.png") == "old")
        #expect(d.read("Pictures/a (2).png") == "new")
    }

    @Test func freeURLCounts() throws {
        let d = try TestDir()
        try d.file("a.png"); try d.file("a (2).png")
        #expect(FileMover.freeURL(d.at("a.png"), fileManager: .default).lastPathComponent == "a (3).png")
        #expect(FileMover.freeURL(d.at("b.png"), fileManager: .default).lastPathComponent == "b.png")
    }

    @Test func skipsVanishedSource() throws {
        let d = try TestDir(), s = try Store.inMemory()
        try d.file("Desktop/a.png")
        let r = try FileMover(store: s).perform([
            FileMove(from: d.at("Desktop/gone.png"), to: d.at("P/gone.png")),
            FileMove(from: d.at("Desktop/a.png"), to: d.at("P/a.png")),
        ], tapID: "t")
        #expect(r.skipped == [d.at("Desktop/gone.png")])
        #expect(r.moved.count == 1)
    }

    @Test func journalsOnlyCompletedMoves() throws {
        let d = try TestDir(), s = try Store.inMemory()
        try d.file("Desktop/a.png")
        _ = try FileMover(store: s).perform([
            FileMove(from: d.at("Desktop/gone.png"), to: d.at("P/gone.png")),
            FileMove(from: d.at("Desktop/a.png"), to: d.at("P/a.png")),
        ], tapID: "t")
        #expect(try s.journal(tapID: "t").map(\.move.to.lastPathComponent) == ["a.png"])
    }

    @Test func undoRestores() throws {
        let d = try TestDir(), s = try Store.inMemory(), m = FileMover(store: s)
        try d.file("Desktop/a.png", "A"); try d.file("Desktop/b.png", "B")
        _ = try m.perform([FileMove(from: d.at("Desktop/a.png"), to: d.at("P/x/a.png")),
                           FileMove(from: d.at("Desktop/b.png"), to: d.at("P/y/b.png"))], tapID: "t")
        let r = try m.undo(tapID: "t")
        #expect(r.moved.count == 2)
        #expect(d.read("Desktop/a.png") == "A" && d.read("Desktop/b.png") == "B")
    }

    @Test func undoSuffixesWhenOriginalTaken() throws {
        let d = try TestDir(), s = try Store.inMemory(), m = FileMover(store: s)
        try d.file("Desktop/a.png", "moved")
        _ = try m.perform([FileMove(from: d.at("Desktop/a.png"), to: d.at("P/a.png"))], tapID: "t")
        try d.file("Desktop/a.png", "newer")
        _ = try m.undo(tapID: "t")
        #expect(d.read("Desktop/a.png") == "newer")
        #expect(d.read("Desktop/a (2).png") == "moved")
    }

    @Test func undoSkipsDeletedFile() throws {
        let d = try TestDir(), s = try Store.inMemory(), m = FileMover(store: s)
        try d.file("Desktop/a.png")
        _ = try m.perform([FileMove(from: d.at("Desktop/a.png"), to: d.at("P/a.png"))], tapID: "t")
        try FileManager.default.removeItem(at: d.at("P/a.png"))
        let r = try m.undo(tapID: "t")
        #expect(r.moved.isEmpty && r.skipped == [d.at("P/a.png")])
    }

    @Test func undoTwiceDoesNothing() throws {
        let d = try TestDir(), s = try Store.inMemory(), m = FileMover(store: s)
        try d.file("Desktop/a.png")
        _ = try m.perform([FileMove(from: d.at("Desktop/a.png"), to: d.at("P/a.png"))], tapID: "t")
        _ = try m.undo(tapID: "t")
        let again = try m.undo(tapID: "t")
        #expect(again.moved.isEmpty)
        #expect(d.exists("Desktop/a.png"))
    }
}
