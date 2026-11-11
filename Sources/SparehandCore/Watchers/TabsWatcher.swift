import Foundation

public struct TopicGroup: Sendable, Equatable {
    public var topic: String
    public var members: [Int]
}

/// Groups tab titles by a shared keyword or phrase ("MBA", "Standing Desks").
/// Apple's sentence embeddings were measured and couldn't separate topics reliably, so this is plain word overlap.
public struct TopicGrouper: Sendable {
    public init() {}

    static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "for", "to", "in", "on", "at", "by", "with", "from", "vs", "v", "versus",
        "best", "top", "review", "guide", "buying", "buy", "how", "what", "why", "which", "are", "is", "it", "its",
        "worth", "new", "near", "me", "my", "your", "you", "today", "this", "that", "do", "does", "can", "should",
        "pro", "plus", "max", "price", "deal", "sale", "official", "site", "home", "page", "online", "free",
        "wirecutter", "reddit", "youtube", "amazon", "google", "wikipedia", "medium", "github", "stack", "overflow",
        "quora", "nytimes", "verge", "cnet", "com", "www",
    ]

    struct Word { let norm: String; let surface: String }

    static func words(_ title: String) -> [Word] {
        title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap { raw in
            let surface = String(raw)
            var w = surface.lowercased()
            guard w.count >= 2, !w.allSatisfy(\.isNumber), !stopwords.contains(w) else { return nil }
            if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") { w.removeLast() }
            guard !stopwords.contains(w) else { return nil }
            return Word(norm: w, surface: surface)
        }
    }

    public func groups(_ titles: [String], minSize: Int) -> [TopicGroup] {
        // term -> (titles containing it, surface text of its first appearance)
        var df: [String: Set<Int>] = [:]
        var surface: [String: String] = [:]
        for (i, title) in titles.enumerated() {
            let ws = Self.words(title)
            var terms: [(String, String)] = ws.map { ($0.norm, $0.surface) }
            for k in 0..<max(0, ws.count - 1) {
                terms.append((ws[k].norm + " " + ws[k + 1].norm, ws[k].surface + " " + ws[k + 1].surface))
            }
            for (norm, surf) in terms {
                df[norm, default: []].insert(i)
                if surface[norm] == nil { surface[norm] = surf }
            }
        }
        let ranked = df.filter { $0.value.count >= minSize }.keys.sorted { a, b in
            let (ca, cb) = (df[a]!.count, df[b]!.count)
            if ca != cb { return ca > cb }
            let (pa, pb) = (a.contains(" "), b.contains(" "))
            if pa != pb { return pa }
            return a < b
        }
        var taken = Set<Int>()
        var out: [TopicGroup] = []
        for term in ranked {
            let members = df[term]!.subtracting(taken)
            guard members.count >= minSize else { continue }
            taken.formUnion(members)
            out.append(TopicGroup(topic: Self.titleCase(surface[term]!), members: members.sorted()))
        }
        return out
    }

    static func titleCase(_ s: String) -> String {
        s.split(separator: " ").map { w in
            w.allSatisfy(\.isUppercase) ? String(w) : w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}

/// Several tabs on one topic, open for a while → one comparison note.
public struct TabsWatcher: Watcher {
    public let id = WatcherID.tabs
    let minTabs: Int
    let minAge: TimeInterval

    public init(minTabs: Int = 5, minAge: TimeInterval = 6 * 3600) {
        self.minTabs = minTabs
        self.minAge = minAge
    }

    public func candidates(_ env: Environment) async throws -> [Candidate] {
        let running = env.runningApps()
        guard !running.isEmpty else { return [] }
        var seen = Set<URL>()
        let tabs = await BrowserTabs.all(runner: env.scripts, running: running).filter { seen.insert($0.url).inserted }
        guard tabs.count >= minTabs else { return [] }
        let now = env.now()
        let ages = try tabs.map { try env.store.firstSeen(url: $0.url, now: now) }
        let minAge = (try env.store.setting("tabs.minAgeSeconds")).flatMap(TimeInterval.init) ?? self.minAge

        return TopicGrouper().groups(tabs.map(\.title), minSize: minTabs).compactMap { group in
            let first = group.members.map { ages[$0] }.min()!
            guard now.timeIntervalSince(first) >= minAge else { return nil }
            let members = group.members.map { tabs[$0] }
            let since = Self.since(first, now: now)
            return Candidate(
                id: Fingerprint.make(id, members.map(\.url.absoluteString)),
                watcher: id,
                summary: "\(members.count) open tabs about \(group.topic), open since \(since).",
                facts: ["count": "\(members.count)", "topic": group.topic, "since": since],
                evidence: members.prefix(3).map { EvidenceItem(label: $0.title, detail: $0.url.host ?? "") },
                plan: .tabsToNote(topic: group.topic, tabs: members),
                noticedAt: now)
        }
    }

    static func since(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 86_400 { return "earlier today" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
