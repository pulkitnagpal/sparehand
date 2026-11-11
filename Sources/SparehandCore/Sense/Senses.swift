import AppKit
import CryptoKit
import Foundation
import IOKit
import Vision

/// What the Mac looked like at one moment: the redacted JSON the models read, plus the typed facts code checks against.
public struct Snapshot: Sendable {
    public var takenAt: Date
    /// Redacted JSON sent to the models.
    public var json: Data
    /// Top-level items per watched folder ("Desktop" → files).
    public var files: [String: [URL]]
    public var tabs: [Tab]
    public var containers: [String]
    public var runningApps: Set<String>
    public var fullscreen: Bool
    public var idleSeconds: Double
    /// Changes when something salient changes (folder contents, tabs, containers, big processes, front app).
    public var salientKey: String

    public var text: String { String(decoding: json, as: UTF8.self) }

    public init(takenAt: Date, json: Data, files: [String: [URL]] = [:], tabs: [Tab] = [], containers: [String] = [],
                runningApps: Set<String> = [], fullscreen: Bool = false, idleSeconds: Double = 0, salientKey: String = "") {
        self.takenAt = takenAt; self.json = json; self.files = files; self.tabs = tabs; self.containers = containers
        self.runningApps = runningApps; self.fullscreen = fullscreen; self.idleSeconds = idleSeconds; self.salientKey = salientKey
    }
}

/// Generic sensing of the Mac. No use-case rules: it reports what is there, and the models decide what matters.
/// `sample()` runs every minute (focus, launches); `snapshot()` builds the full picture.
public actor Senses {
    public static let folders = ["Desktop", "Downloads"]
    public static let imageKinds: Set<String> = ["png", "jpg", "jpeg", "heic"]

    let env: Environment
    var appMinutesToday: [String: Double] = [:]
    var launches: [(String, String)] = []
    var focus: [(app: String, title: String, at: Date)] = []
    var previousRunning: Set<String>?
    var knownFiles: [String: Set<String>] = [:]
    var historyOffset: UInt64 = 0
    var day = Calendar.current.startOfDay(for: Date())

    public init(env: Environment) {
        self.env = env
        let hist = env.home.appendingPathComponent(".zsh_history").path
        historyOffset = ((try? FileManager.default.attributesOfItem(atPath: hist)[.size]) as? NSNumber)?.uint64Value ?? 0
        for f in Self.folders { knownFiles[f] = Set(Self.list(env.home.appendingPathComponent(f)).map(\.lastPathComponent)) }
    }

    // MARK: - every minute

    public func sample() {
        let now = env.now()
        let today = Calendar.current.startOfDay(for: now)
        if today != day { day = today; appMinutesToday = [:]; launches = [] }
        let front = Self.frontWindow()
        let running = env.runningApps()
        if let prev = previousRunning {
            for app in running.subtracting(prev).sorted() { launches.append((Self.clock(now), app)) }
        }
        previousRunning = running
        if Self.idleSeconds() < 60, !front.app.isEmpty {
            appMinutesToday[front.app, default: 0] += 1
            focus.append((front.app, Redactor.text(front.title), now))
        }
        focus.removeAll { now.timeIntervalSince($0.at) > 900 }
    }

    // MARK: - the full picture

    public func snapshot() async -> Snapshot {
        let now = env.now()
        let front = Self.frontWindow()
        let idle = Self.idleSeconds()
        let running = env.runningApps()
        var json: [String: Any] = [
            "time": Self.longClock(now),
            "user_idle_seconds": Int(idle),
            "front_app_now": ["app": front.app, "title": Redactor.text(front.title), "fullscreen": front.fullscreen],
            "visible_windows_now": front.visible.prefix(12).map(Redactor.text),
        ]
        var focusCount: [String: Int] = [:]
        for f in focus { focusCount["\(f.app) — \(f.title.prefix(70))", default: 0] += 1 }
        json["focus_last_15_min"] = focusCount.sorted { $0.value > $1.value }.prefix(8).map { ["what": $0.key, "minutes": $0.value] }
        json["app_minutes_today"] = Dictionary(uniqueKeysWithValues: appMinutesToday.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, Int($0.value)) })
        json["app_launches_today"] = launches.suffix(20).map { "\($0.0) \($0.1)" }
        json["running_apps"] = running.sorted()

        // Folders: counts, kinds, newest, new since the last snapshot, and the text in a few images.
        var files: [String: [URL]] = [:]
        var folderJSON: [String: Any] = [:]
        var ocrTargets: [URL] = []
        for name in Self.folders {
            let dir = env.home.appendingPathComponent(name)
            let items = Self.list(dir)
            files[name] = items
            let known = knownFiles[name] ?? []
            let new = items.filter { !known.contains($0.lastPathComponent) }
            knownFiles[name] = Set(items.map(\.lastPathComponent))
            folderJSON[name] = Self.describe(items, new: new, now: now)
            let images = items.filter { Self.imageKinds.contains($0.pathExtension.lowercased()) }
            ocrTargets += new.filter { Self.imageKinds.contains($0.pathExtension.lowercased()) }.prefix(3)
            if images.count >= 6 { ocrTargets += images.shuffled().prefix(12) }
        }
        json["folders"] = folderJSON
        let ocr = Self.ocr(Array(Set(ocrTargets)).prefix(16).map { $0 })
        json["image_text_samples"] = Dictionary(uniqueKeysWithValues: ocr.map { ($0.key.lastPathComponent, $0.value) })

        // Browser tabs (never launches a browser), with how long each has been open.
        let tabs = await BrowserTabs.all(runner: env.scripts, running: running)
        json["browser_tabs"] = tabs.prefix(60).map { t -> [String: String] in
            let since = (try? env.store.firstSeen(url: t.url, now: now)) ?? now
            return ["title": Redactor.text(String(t.title.prefix(110))), "url": Redactor.url(t.url.absoluteString),
                    "browser": t.browser, "open_for": Self.age(now.timeIntervalSince(since))]
        }
        json["browser_tab_count"] = tabs.count

        let (cmds, offset) = Self.history(env.home.appendingPathComponent(".zsh_history"), from: historyOffset)
        historyOffset = offset
        json["terminal_commands_since_last_look"] = Array(cmds.suffix(20))
        let procs = Self.processes()
        json["top_processes"] = procs
        let containers = Self.containers()
        if !containers.isEmpty { json["containers"] = containers }
        json["memory"] = Self.memory()
        json["disk"] = Self.disk()
        if let b = Self.battery() { json["battery"] = b }
        json["not_sensed"] = ["calendar", "mail", "notifications", "screen content beyond window titles"]

        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        let salient = [
            Self.folders.map { "\($0):\(files[$0]?.count ?? 0)" }.joined(separator: ","),
            tabs.map(\.url.absoluteString).sorted().joined(separator: ","),
            containers.compactMap { $0["name"] as? String }.joined(separator: ","),
            procs.prefix(5).compactMap { $0["name"] as? String }.joined(separator: ","),
        ].joined(separator: "|")
        return Snapshot(takenAt: now, json: data, files: files, tabs: tabs,
                        containers: containers.compactMap { $0["name"] as? String }, runningApps: running,
                        fullscreen: front.fullscreen, idleSeconds: idle,
                        salientKey: SHA256.hash(data: Data(salient.utf8)).map { String(format: "%02x", $0) }.joined())
    }

    // MARK: - sensors

    nonisolated static func list(_ dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
                                                        options: [.skipsHiddenFiles])) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    nonisolated static func describe(_ items: [URL], new: [URL], now: Date) -> [String: Any] {
        var kinds: [String: Int] = [:]
        var total = 0
        var dated: [(URL, Date, Int)] = []
        for u in items {
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
            let kind = v?.isDirectory == true ? "folder" : (u.pathExtension.isEmpty ? "no extension" : "." + u.pathExtension.lowercased())
            kinds[kind, default: 0] += 1
            total += v?.fileSize ?? 0
            dated.append((u, v?.contentModificationDate ?? now, v?.fileSize ?? 0))
        }
        let newest = dated.sorted { $0.1 > $1.1 }.prefix(8).map { u, d, s in
            "\(u.lastPathComponent) (\(age(now.timeIntervalSince(d))) ago\(s > 1_000_000 ? ", \(String(format: "%.1f", Double(s) / 1e6)) MB" : ""))"
        }
        let oldest = dated.map(\.1).min().map { age(now.timeIntervalSince($0)) } ?? "n/a"
        return ["items": items.count, "by_kind": kinds.sorted { $0.value > $1.value }.prefix(8).reduce(into: [String: Int]()) { $0[$1.key] = $1.value },
                "total_size_mb": total / 1_000_000, "oldest_item_age": oldest, "newest": newest.map(Redactor.text),
                "new_since_last_look": new.prefix(12).map { Redactor.text($0.lastPathComponent) }]
    }

    nonisolated public static func ocr(_ urls: [URL]) -> [URL: String] {
        var out: [URL: String] = [:]
        for u in urls {
            guard let img = NSImage(contentsOf: u), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .fast
            try? VNImageRequestHandler(cgImage: cg).perform([req])
            let text = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            out[u] = Redactor.text(String(text.prefix(220)))
        }
        return out
    }

    nonisolated static func frontWindow() -> (app: String, title: String, fullscreen: Bool, visible: [String]) {
        let front = NSWorkspace.shared.frontmostApplication
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let normal = list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
        let w = normal.first { ($0[kCGWindowOwnerPID as String] as? pid_t) == front?.processIdentifier }
        var fullscreen = false
        if let b = w?[kCGWindowBounds as String] as? [String: CGFloat] {
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
            CGGetActiveDisplayList(8, &ids, &n)
            fullscreen = ids.prefix(Int(n)).contains { CGDisplayBounds($0).equalTo(r) }
        }
        let visible = normal.compactMap { w -> String? in
            guard let owner = w[kCGWindowOwnerName as String] as? String else { return nil }
            let t = (w[kCGWindowName as String] as? String) ?? ""
            return t.isEmpty ? owner : "\(owner) — \(t)"
        }
        return (front?.localizedName ?? "", (w?[kCGWindowName as String] as? String) ?? "", fullscreen, visible)
    }

    nonisolated public static func idleSeconds() -> Double {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &it) == KERN_SUCCESS else { return 0 }
        let e = IOIteratorNext(it); defer { IOObjectRelease(e); IOObjectRelease(it) }
        let ns = (IORegistryEntryCreateCFProperty(e, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue ?? 0
        return ns / 1e9
    }

    nonisolated static func processes() -> [[String: Any]] {
        var groups: [String: (ram: Int, cpu: Double, n: Int)] = [:]
        for line in Shell.run("/bin/ps", ["-axo", "rss=,pcpu=,comm="]).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let rss = Int(parts[0]), let cpu = Double(parts[1]) else { continue }
            let comm = String(parts[2])
            let name = comm.range(of: #"/([^/]+)\.app/"#, options: .regularExpression).map { String(comm[$0].dropFirst().dropLast(5)) }
                ?? (comm as NSString).lastPathComponent
            let g = groups[name] ?? (0, 0, 0)
            groups[name] = (g.ram + rss / 1024, g.cpu + cpu, g.n + 1)
        }
        return groups.sorted { $0.value.ram > $1.value.ram }.prefix(10).map {
            ["name": $0.key, "ram_mb": $0.value.ram, "cpu_pct": (($0.value.cpu * 10).rounded() / 10), "processes": $0.value.n]
        }
    }

    nonisolated static func containers() -> [[String: Any]] {
        guard let docker = Shell.which("docker") else { return [] }
        let out = Shell.run(docker, ["ps", "--format", "{{.Names}}\t{{.Status}}"], timeout: 6)
        guard !out.isEmpty else { return [] }
        var mem: [String: String] = [:]
        for l in Shell.run(docker, ["stats", "--no-stream", "--format", "{{.Name}}\t{{.MemUsage}}"], timeout: 12).split(separator: "\n") {
            let p = l.split(separator: "\t"); if p.count == 2 { mem[String(p[0])] = String(p[1].split(separator: "/").first ?? "").trimmingCharacters(in: .whitespaces) }
        }
        return out.split(separator: "\n").compactMap { l in
            let p = l.split(separator: "\t", maxSplits: 1); guard p.count == 2 else { return nil }
            return ["name": String(p[0]), "status": String(p[1]), "memory": mem[String(p[0])] ?? "?"]
        }
    }

    nonisolated static func memory() -> [String: Any] {
        let out = Shell.run("/usr/bin/memory_pressure", ["-Q"])
        var m: [String: Any] = ["total_gb": Int(ProcessInfo.processInfo.physicalMemory / 1_000_000_000)]
        if let r = out.range(of: #"\d+(?=%)"#, options: .regularExpression), let v = Int(out[r]) { m["free_pct"] = v }
        return m
    }

    nonisolated static func disk() -> [String: Any] {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return ["free_gb": Int((v?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000), "total_gb": (v?.volumeTotalCapacity ?? 0) / 1_000_000_000]
    }

    nonisolated static func battery() -> [String: Any]? {
        let out = Shell.run("/usr/bin/pmset", ["-g", "batt"])
        guard let r = out.range(of: #"\d+%"#, options: .regularExpression) else { return nil }
        return ["percent": Int(out[r].dropLast()) ?? 0, "on_power": out.contains("AC Power")]
    }

    nonisolated static func history(_ file: URL, from offset: UInt64) -> ([String], UInt64) {
        guard let h = try? FileHandle(forReadingFrom: file) else { return ([], offset) }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? offset
        guard end > offset else { return ([], end) }
        try? h.seek(toOffset: offset)
        let data = (try? h.readToEnd()) ?? Data()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map { line -> String in
            var s = String(line)
            if let r = s.range(of: #"^: \d+:\d+;"#, options: .regularExpression) { s.removeSubrange(r) }
            return Redactor.text(String(s.prefix(160)))
        }.filter { !$0.isEmpty }
        return (lines, end)
    }

    nonisolated static func age(_ sec: TimeInterval) -> String {
        let s = max(0, sec)
        if s < 3600 { return "\(Int(s / 60)) min" }
        if s < 86_400 { return String(format: "%.1f h", s / 3600) }
        return "\(Int(s / 86_400)) days"
    }

    nonisolated static func clock(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEE HH:mm"; return f.string(from: d) }
    nonisolated static func longClock(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEE d MMM HH:mm"; return f.string(from: d) }
}
