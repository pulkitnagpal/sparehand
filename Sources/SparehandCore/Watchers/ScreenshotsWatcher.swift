import Foundation

/// Many old screenshots on the Desktop → move them into Pictures/Screenshots/<YYYY-MM>/.
public struct ScreenshotsWatcher: Watcher {
    public let id = WatcherID.screenshots
    let minCount: Int
    let keepRecentDays: Int

    public init(minCount: Int = 20, keepRecentDays: Int = 2) {
        self.minCount = minCount
        self.keepRecentDays = keepRecentDays
    }

    // "Screenshot 2026-09-28 at 10.14.32.png", "Screen Recording 2026-09-28 at 10.14.32.mov"
    static let pattern = try! NSRegularExpression(
        pattern: #"^(Screenshot|Screen Recording) (\d{4})-(\d{2})-\d{2} at .+\.(png|jpg|jpeg|heic|mov)$"#,
        options: [.caseInsensitive])

    /// "2026-09" for a screenshot file name, nil for anything else.
    static func month(of name: String) -> String? {
        let ns = name as NSString
        guard let m = pattern.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 2)) + "-" + ns.substring(with: m.range(at: 3))
    }

    static func monthName(_ yyyymm: String) -> String {
        let parse = DateFormatter(); parse.locale = Locale(identifier: "en_US_POSIX"); parse.dateFormat = "yyyy-MM"
        let show = DateFormatter(); show.locale = Locale(identifier: "en_US_POSIX"); show.dateFormat = "LLLL yyyy"
        return parse.date(from: yyyymm).map(show.string(from:)) ?? yyyymm
    }

    public func candidates(_ env: Environment) async throws -> [Candidate] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: env.desktop, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey]) else { return [] }
        let cutoff = env.now().addingTimeInterval(-Double(keepRecentDays) * 86_400)
        var old: [(url: URL, month: String)] = []
        var kept = 0
        for url in items {
            guard let month = Self.month(of: url.lastPathComponent) else { continue }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created > cutoff { kept += 1 } else { old.append((url, month)) }
        }
        guard old.count >= minCount, old.count > 0 else { return [] }

        let moves = old.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }.map {
            FileMove(from: $0.url, to: env.screenshotsRoot.appendingPathComponent($0.month).appendingPathComponent($0.url.lastPathComponent))
        }
        let buckets = Dictionary(grouping: old, by: \.month).mapValues(\.count)
        let oldest = Self.monthName(buckets.keys.min()!)
        let evidence = buckets.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key > $1.key }.prefix(3)
            .map { EvidenceItem(label: Self.monthName($0.key), detail: "\($0.value) \($0.value == 1 ? "file" : "files")") }
        let staying = kept == 1 ? "1 recent one would stay" : "\(kept) recent ones would stay"
        return [Candidate(
            id: Fingerprint.make(id, old.map { $0.url.lastPathComponent }),
            watcher: id,
            summary: "\(old.count) screenshots are on the Desktop, oldest from \(oldest); \(staying).",
            facts: ["count": "\(old.count)", "kept": "\(kept)", "oldestMonth": oldest],
            evidence: Array(evidence),
            plan: .moveFiles(moves),
            noticedAt: env.now())]
    }
}
