import Foundation

/// A big Bin → permanently delete its largest items (after an explicit confirmation in the app).
public struct BinWatcher: Watcher {
    public let id = WatcherID.bin
    let minTotalBytes: Int64
    let minItemBytes: Int64
    let maxItems: Int

    public init(minTotalBytes: Int64 = 5_000_000_000, minItemBytes: Int64 = 500_000_000, maxItems: Int = 3) {
        self.minTotalBytes = minTotalBytes
        self.minItemBytes = minItemBytes
        self.maxItems = maxItems
    }

    public func candidates(_ env: Environment) async throws -> [Candidate] {
        guard BinAccess.canRead(env.trash),
              let items = try? FileManager.default.contentsOfDirectory(at: env.trash, includingPropertiesForKeys: nil) else { return [] }
        let sized = items.filter { $0.lastPathComponent != ".DS_Store" }.map { ($0, BinAccess.size(of: $0)) }
        let total = sized.reduce(Int64(0)) { $0 + $1.1 }
        guard total >= minTotalBytes else { return [] }
        let picks = sized.filter { $0.1 >= minItemBytes }.sorted { $0.1 > $1.1 }.prefix(maxItems)
        guard !picks.isEmpty else { return [] }
        let picked = picks.reduce(Int64(0)) { $0 + $1.1 }
        let n = picks.count
        return [Candidate(
            id: Fingerprint.make(id, picks.map { $0.0.lastPathComponent }),
            watcher: id,
            summary: "The Bin holds \(BinAccess.format(total)); the \(n) largest \(n == 1 ? "item is" : "items are") \(BinAccess.format(picked)).",
            facts: ["totalGB": BinAccess.format(total), "itemsGB": BinAccess.format(picked), "n": "\(n)"],
            evidence: picks.map { EvidenceItem(label: $0.0.lastPathComponent, detail: BinAccess.format($0.1)) },
            plan: .deletePermanently(picks.map { $0.0 }),
            noticedAt: env.now())]
    }
}

public enum BinAccess {
    /// False when macOS hides the Bin from us (no Full Disk Access).
    public static func canRead(_ trash: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) != nil
    }

    /// Logical size, folders summed recursively (what Finder shows).
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileSizeKey, .fileSizeKey]
        let v = try? url.resourceValues(forKeys: keys)
        guard v?.isDirectory == true else { return Int64(v?.totalFileSize ?? v?.fileSize ?? 0) }
        var sum: Int64 = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) {
            for case let f as URL in e {
                let fv = try? f.resourceValues(forKeys: keys)
                if fv?.isDirectory != true { sum += Int64(fv?.totalFileSize ?? fv?.fileSize ?? 0) }
            }
        }
        return sum
    }

    static func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes).replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
