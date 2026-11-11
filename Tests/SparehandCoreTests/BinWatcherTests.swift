import Foundation
import Testing
@testable import SparehandCore

@Suite struct BinWatcherTests {
    func sparse(_ d: TestDir, _ rel: String, bytes: UInt64) throws {
        let u = try d.file(rel, "")
        let h = try FileHandle(forWritingTo: u)
        try h.truncate(atOffset: bytes)
        try h.close()
    }

    @Test func belowTotalNoCandidate() async throws {
        let d = try TestDir()
        try sparse(d, ".Trash/a.dmg", bytes: 1_000_000_000)
        #expect(try await BinWatcher().candidates(env(d)).isEmpty)
    }

    @Test func picksLargestOverItemMinimum() async throws {
        let d = try TestDir()
        try sparse(d, ".Trash/Xcode_26.dmg", bytes: 6_200_000_000)
        try sparse(d, ".Trash/recording.mov", bytes: 2_100_000_000)
        try sparse(d, ".Trash/folder/big.tar", bytes: 700_000_000)
        try sparse(d, ".Trash/folder/small.txt", bytes: 1_000)
        try sparse(d, ".Trash/tiny.txt", bytes: 400_000_000)
        try sparse(d, ".Trash/huge2.iso", bytes: 3_000_000_000)
        let c = try #require(try await BinWatcher().candidates(env(d)).first)
        guard case .deletePermanently(let urls) = c.plan else { Issue.record("plan"); return }
        #expect(urls.map(\.lastPathComponent) == ["Xcode_26.dmg", "huge2.iso", "recording.mov"])
        #expect(c.facts["n"] == "3")
        #expect(c.facts["totalGB"] == "12.4 GB")
        #expect(c.facts["itemsGB"] == "11.3 GB")
        #expect(c.evidence.first == EvidenceItem(label: "Xcode_26.dmg", detail: "6.2 GB"))
        #expect(c.summary == "The Bin holds 12.4 GB; the 3 largest items are 11.3 GB.")
    }

    @Test func countsFoldersRecursively() async throws {
        let d = try TestDir()
        try sparse(d, ".Trash/project/a.bin", bytes: 3_000_000_000)
        try sparse(d, ".Trash/project/sub/b.bin", bytes: 3_000_000_000)
        let c = try #require(try await BinWatcher().candidates(env(d)).first)
        #expect(c.evidence.first == EvidenceItem(label: "project", detail: "6 GB"))
    }

    @Test func unreadableBinYieldsNothing() async throws {
        let d = try TestDir()
        try sparse(d, ".Trash/a.dmg", bytes: 9_000_000_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: d.at(".Trash").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.at(".Trash").path) }
        #expect(!BinAccess.canRead(d.at(".Trash")))
        #expect(try await BinWatcher().candidates(env(d)).isEmpty)
    }
}
