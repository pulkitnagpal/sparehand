# Sparehand Milestone 1 (the two launch demos) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working Sparehand menu-bar app that runs Demo 1 (screenshots tidy + Bin cleanup, invisible, with undo) and Demo 2 (tabs → comparison note, done on Sparehand's own watchable screen with Claude Code) for real on a Mac.

**Architecture:** A Swift package with a pure-logic library (`SparehandCore`: watchers, judge client, store, journal, job/script builders), a small Objective-C target for the private virtual-display API (`CVirtualDisplay`), the SwiftUI/AppKit menu-bar app (`SparehandApp`) and a CLI (`sparehand`) used for debugging, demo seeding and the watchable Claude Code runner. The local judge is `mlx_lm.server` on localhost; heavy work is `claude -p` on the user's subscription; apps are driven with AppleScript, never by clicking pixels.

**Tech Stack:** Swift 6.3 (language mode 5), SwiftPM, swift-testing (via `scripts/test.sh`), SwiftUI + AppKit, ScreenCaptureKit, NaturalLanguage (`NLEmbedding`), SQLite3 (system), Objective-C for `CGVirtualDisplay`, Python `mlx-lm` 0.32.x in a uv venv for the judge server, Claude Code 2.1.x CLI.

**Spec:** `docs/superpowers/specs/2026-11-11-sparehand-design.md` (approved 2026-11-11), POCs in `docs/superpowers/specs/2026-11-11-sparehand-pocs.md`. Design canvas: https://claude.ai/artifact/F86WB16SPiDVKKn6QkQKru

## Global Constraints

- macOS 26+, Apple silicon. Build with the Command Line Tools only (no Xcode): `swift build`, `scripts/test.sh`.
- Swift tools 6.3, `swiftLanguageModes: [.v5]`, platforms `.macOS(.v26)`.
- MIT licence. Standalone: no code, files or dependency from Quietkey.
- Nothing leaves the Mac except a Claude Code job the user approved (and the one-time model download).
- Nothing happens without approval. Permanent deletion needs a specific "can't be undone" confirmation. Every reversible change is journalled and undoable.
- Sparehand only touches windows it created, addressed by window id; it never moves, types into, or streams the user's windows.
- The virtual display gets a fresh random serial number every time it is created.
- No pixel-clicking "computer use". Apps are driven by AppleScript; Claude only returns text.
- No taps while the frontmost app is full screen or a call app (`us.zoom.xos`, `com.apple.FaceTime`, `com.microsoft.teams2`); taps wait in the feed.
- Judge model: `mlx-community/Qwen3.5-4B-MLX-4bit`, served by `mlx_lm.server --port 8765 --chat-template-args '{"enable_thinking":false}'`. Temperature 0. The model never does arithmetic or grouping; code does.
- Visual language: surfaces `#F7F6F3`/`#FFFFFF`, ink `#16161A`, body `#3F3F46`, muted `#6B6B74`, hairline `#E6E3DD`, decide-accent `#C2410C`, working-accent `#0F766E`; Space Grotesk headings (fallback system font), Inter/system body; hand glyph as the mark. Light theme everywhere, including the live viewer.
- Bundle id `dev.sparehand.app`, app name `Sparehand`, data in `~/Library/Application Support/Sparehand/`.

## Review Focus

1. Judge server not running, slow (>3 s) or returning junk → a rule-based card is used instead; no crash, no silent drop. (Task 6 test `fallsBackWhenServerDown`, `fallsBackOnBadJSON`.)
2. Moving screenshots when the destination name exists, the month folder is missing, or a source vanished mid-run → suffix ` (2)`, create folders, skip missing, journal only completed moves. (Task 3 tests.)
3. Undo when the original path is now taken or the moved file was deleted → restore with a suffix or report it skipped; never overwrite. (Task 3 tests.)
4. Claude Code missing, logged out, erroring, or returning something that isn't a table (or HTML with scripts) → job fails visibly ("Needs you"), no note created; HTML is sanitised to table tags only. (Task 8 tests.)
5. User already has Terminal/Notes/browser windows open, or a browser denies Automation → only Sparehand-created windows are moved/streamed; Notes is not shown on Sparehand's screen if it already has windows (note is still created); tabs watcher returns nothing rather than failing. (Task 7 test `deniedAutomationYieldsNoTabs`, Task 9 test `notesSkipsShowWhenUserWindowsOpen`, Task 10 manual check.)

---

## File structure

```
Package.swift
scripts/test.sh                      swift-testing with CLT frameworks
scripts/judge-server.sh              start/stop the MLX judge server (uv venv in Application Support)
scripts/bundle-app.sh                build dist/Sparehand.app + dist/sparehand, sign (stable identity if present, else ad-hoc)
Resources/Info.plist                 LSUIElement, bundle id, usage strings (Apple Events, Calendars n/a)
Sources/CVirtualDisplay/             include/CVirtualDisplay.h (private class decls), shim.m (create/destroy helpers)
Sources/SparehandCore/
  Model/Candidate.swift              WatcherID, Candidate, EvidenceItem, ActionPlan, FileMove, Tab
  Model/Tap.swift                    Tap, TapState, Verdict
  Store/Store.swift                  SQLite: taps, tab first-seen, journal, settings
  Fix/Journal.swift                  JournalEntry, FileMover (move with collision handling, undo)
  Watchers/Watcher.swift             Watcher protocol, Environment (paths, clock, fs)
  Watchers/ScreenshotsWatcher.swift
  Watchers/BinWatcher.swift
  Watchers/TabsWatcher.swift         + TopicClusterer
  Judge/Judge.swift                  Judge protocol, LocalModelJudge (HTTP), RuleJudge, FallbackJudge, JudgePrompt
  Apps/AppleScript.swift             ScriptRunner protocol, OSAScriptRunner, escaping
  Apps/BrowserTabs.swift             tab-listing scripts + parsers (Chrome family, Safari)
  Apps/Notes.swift                   NotesWriter (script builder)
  Apps/Terminal.swift                TerminalLauncher (script builder, window id)
  Jobs/ClaudeJob.swift               prompt builder, stream-json parser, table extraction, HTML sanitiser
  Engine/Engine.swift                runs watchers, judges, dedups, rate-limits, quiet rules; executes approved plans
Sources/SparehandApp/
  SparehandApp.swift                 @main, MenuBarExtra, app delegate
  UI/Theme.swift, UI/TapPanel.swift, UI/TapCard.swift, UI/FeedView.swift, UI/OnboardingView.swift
  AgentScreen/AgentScreen.swift      virtual display lifecycle, window placement
  AgentScreen/LiveViewer.swift       SCStream of Sparehand windows → PiP panel + full-screen window
  AgentScreen/LiveViews.swift        SwiftUI PiP + full-screen views (light theme)
Sources/sparehand/                   CLI: main.swift, Commands (scan, judge, claude-run, demo-seed, undo)
Tests/SparehandCoreTests/            one test file per Core file + Fixtures/claude-stream.jsonl
```

---

### Task 1: Package, models and test harness

**Files:** Create `Package.swift`, `scripts/test.sh`, `LICENSE` (MIT, "Pulkit Nagpal"), `.gitignore` (`.build/`, `dist/`), `Sources/SparehandCore/Model/Candidate.swift`, `Sources/SparehandCore/Model/Tap.swift`, `Tests/SparehandCoreTests/ModelTests.swift`.

**Interfaces — Produces:**
```swift
public enum WatcherID: String, Codable, Sendable, CaseIterable { case screenshots, bin, tabs }
public struct EvidenceItem: Codable, Sendable, Equatable { public var label: String; public var detail: String }
public struct FileMove: Codable, Sendable, Equatable { public var from: URL; public var to: URL }
public struct Tab: Codable, Sendable, Equatable, Hashable { public var browser: String; public var title: String; public var url: URL }
public enum ActionPlan: Codable, Sendable, Equatable {
  case moveFiles([FileMove])                 // reversible
  case deletePermanently([URL])              // not reversible
  case tabsToNote(topic: String, tabs: [Tab])
  public var isReversible: Bool { get }      // true for moveFiles and tabsToNote (undo = delete the note)
}
public struct Candidate: Codable, Sendable, Equatable, Identifiable {
  public var id: String            // stable fingerprint: watcher + sorted item keys, SHA-256 hex prefix 16
  public var watcher: WatcherID
  public var summary: String       // one plain-English line for the judge, numbers already computed
  public var evidence: [EvidenceItem]
  public var plan: ActionPlan
  public var noticedAt: Date
}
public struct Verdict: Codable, Sendable, Equatable { public var show: Bool; public var value: Int; public var title: String; public var body: String; public var actionLabel: String; public var source: Source; public enum Source: String, Codable, Sendable { case model, rules } }
public enum TapState: String, Codable, Sendable { case pending, approved, running, done, failed, dismissed, undone }
public struct Tap: Codable, Sendable, Equatable, Identifiable { public var id: String /* = candidate.id */; public var candidate: Candidate; public var verdict: Verdict; public var state: TapState; public var createdAt: Date; public var finishedAt: Date?; public var note: String? /* failure text */; public var resultRef: String? /* e.g. the created note's id, used by undo */ }
public enum Fingerprint { public static func make(_ watcher: WatcherID, _ keys: [String]) -> String }
```

- [ ] **Step 1:** Write `Package.swift`: products `SparehandCore` (library), `SparehandApp` and `sparehand` (executables), target `CVirtualDisplay` (Objective-C, linker `CoreGraphics`), test target `SparehandCoreTests`. Copy `scripts/test.sh` behaviour: when `xcode-select -p` contains `CommandLineTools`, run `swift test` with `-F`/`-rpath` to `/Library/Developer/CommandLineTools/Library/Developer/Frameworks` and `.../usr/lib` (write it fresh; same four flag pairs).
- [ ] **Step 2: Failing tests** in `ModelTests.swift`: `candidateRoundTrips` (encode/decode equal for each `ActionPlan` case), `fingerprintIsOrderIndependent` (`make(.screenshots, ["b","a"]) == make(.screenshots, ["a","b"])`, length 16), `reversibility` (`.moveFiles([]).isReversible`, `!.deletePermanently([]).isReversible`).
- [ ] **Step 3:** Run `scripts/test.sh` → FAIL (types missing).
- [ ] **Step 4:** Implement the types above (Fingerprint via CryptoKit SHA256 of `watcher.rawValue + "\n" + sorted keys joined by "\n"`).
- [ ] **Step 5:** `scripts/test.sh` → PASS. Commit `feat: package skeleton and core models`.

### Task 2: Store

**Files:** Create `Sources/SparehandCore/Store/Store.swift`, `Tests/SparehandCoreTests/StoreTests.swift`.

**Interfaces — Consumes:** Task 1 models. **Produces:**
```swift
public final class Store: @unchecked Sendable {      // serial queue inside
  public init(path: URL) throws                      // creates tables; ":memory:" via Store.inMemory()
  public static func inMemory() throws -> Store
  public func upsert(_ tap: Tap) throws
  public func tap(id: String) throws -> Tap?
  public func taps(states: Set<TapState>) throws -> [Tap]   // newest first
  public func lastShown(watcher: WatcherID) throws -> Date?
  public func firstSeen(url: URL, now: Date) throws -> Date // inserts now if new
  public func appendJournal(_ e: JournalEntry) throws
  public func journal(tapID: String) throws -> [JournalEntry]
  public func setting(_ key: String) throws -> String?; public func setSetting(_ key: String, _ value: String) throws
}
```
Tables: `taps(id PK, json, state, created_at)`, `tab_seen(url PK, first_seen)`, `journal(id INTEGER PK, tap_id, json, at)`, `settings(key PK, value)`. Store taps as JSON blobs. `JournalEntry` is defined in Task 3; declare it here as `public struct JournalEntry: Codable, Sendable, Equatable { public var tapID: String; public var move: FileMove; public var at: Date }` in `Fix/Journal.swift` (created in this task, extended in Task 3).

- [ ] Tests: `tapRoundTrip`, `filtersByState`, `firstSeenIsSticky` (second call returns the first date), `journalForTap`, `settings`. Run → FAIL → implement with `import SQLite3` → PASS → commit `feat: sqlite store`.

### Task 3: File mover with undo journal

**Files:** Modify `Sources/SparehandCore/Fix/Journal.swift`; Test `Tests/SparehandCoreTests/JournalTests.swift`.

**Interfaces — Produces:**
```swift
public struct MoveReport: Sendable, Equatable { public var moved: [FileMove]; public var skipped: [URL] }
public struct FileMover: Sendable {
  public init(store: Store, fileManager: FileManager = .default)
  public func perform(_ moves: [FileMove], tapID: String) throws -> MoveReport   // journals each completed move
  public func undo(tapID: String) throws -> MoveReport                           // moves back, newest first
  public static func freeURL(_ url: URL, fileManager: FileManager) -> URL        // "a.png" -> "a (2).png", "a (3).png", …
}
```
- [ ] Tests (temp dirs): `movesAndCreatesFolders`, `suffixesOnCollision` (destination exists → `name (2).png`), `skipsVanishedSource`, `undoRestores`, `undoSuffixesWhenOriginalTaken`, `undoSkipsDeletedFile`, `journalsOnlyCompletedMoves`. Run → FAIL → implement → PASS → commit `feat: file mover with undo journal`.

### Task 4: Screenshots watcher

**Files:** Create `Sources/SparehandCore/Watchers/Watcher.swift`, `Sources/SparehandCore/Watchers/ScreenshotsWatcher.swift`; Test `Tests/SparehandCoreTests/ScreenshotsWatcherTests.swift`.

**Interfaces — Produces:**
```swift
public struct Environment: Sendable {
  public var home: URL; public var now: @Sendable () -> Date; public var store: Store; public var scripts: ScriptRunner
  public var desktop: URL { home/Desktop }; public var trash: URL { home/.Trash }; public var screenshotsRoot: URL { home/Pictures/Screenshots }
  public static func live(store: Store) -> Environment   // home = $SPAREHAND_HOME if set (tests, manual checks), else the real home; scripts = OSAScriptRunner()
}
public protocol Watcher: Sendable { var id: WatcherID { get }; func candidates(_ env: Environment) async throws -> [Candidate] }
public struct ScreenshotsWatcher: Watcher { public init(minCount: Int = 20, keepRecentDays: Int = 2) }
```
Rules: a screenshot is a Desktop file whose name matches `^(Screenshot|Screen Recording) \d{4}-\d{2}-\d{2} at .+\.(png|jpg|jpeg|heic|mov)$`. Only files older than `keepRecentDays` (by creation date) count. If count ≥ `minCount`, one candidate: plan `.moveFiles` to `screenshotsRoot/YYYY-MM/<name>` using the date in the file name; summary `"<N> screenshots are on the Desktop, oldest from <Month YYYY>; <K> recent ones would stay."`; evidence = up to 3 month buckets with counts (`"September 2026" / "112 files"`). Fingerprint keys = file names. (`ScriptRunner` is declared in Task 7; for this task define `public protocol ScriptRunner: Sendable { func run(_ source: String) async throws -> String }` in `Apps/AppleScript.swift` now.)
- [ ] Tests: `belowThresholdNoCandidate`, `groupsByMonthFromName`, `keepsRecent`, `ignoresNonScreenshots` (`Screenshot notes.txt`, `IMG_1.png`), `fingerprintStableAcrossRuns`. FAIL → implement → PASS → commit `feat: screenshots watcher`.

### Task 5: Bin watcher

**Files:** Create `Sources/SparehandCore/Watchers/BinWatcher.swift`; Test `Tests/SparehandCoreTests/BinWatcherTests.swift`.

**Interfaces — Produces:** `public struct BinWatcher: Watcher { public init(minTotalBytes: Int64 = 5_000_000_000, minItemBytes: Int64 = 500_000_000, maxItems: Int = 3) }` and `public enum BinAccess { public static func canRead(_ trash: URL) -> Bool }`.
Rules: if the Bin can't be listed (no Full Disk Access) → no candidates (and `canRead` false, used by onboarding). Total allocated size of top-level items (directories summed recursively) ≥ `minTotalBytes` → candidate with plan `.deletePermanently` of the largest `maxItems` items that are each ≥ `minItemBytes`; summary `"The Bin holds <X> GB; the <n> largest items are <Y> GB."`; evidence = each item (`name` / `"6.2 GB"`). Sizes formatted with `ByteCountFormatter` `.file`.
- [ ] Tests (temp "trash" dir with sparse files via `FileHandle.truncate`): `belowTotalNoCandidate`, `picksLargestOverItemMinimum`, `unreadableBinYieldsNothing` (dir with `chmod 000`). FAIL → implement → PASS → commit `feat: bin watcher`.

### Task 6: Judge (local model + rules fallback) and judge server script

**Files:** Create `Sources/SparehandCore/Judge/Judge.swift`, `scripts/judge-server.sh`; Test `Tests/SparehandCoreTests/JudgeTests.swift`.

**Interfaces — Produces:**
```swift
public protocol Judge: Sendable { func verdict(for c: Candidate) async -> Verdict }
public struct LocalModelJudge: Judge {
  public init(endpoint: URL = URL(string: "http://127.0.0.1:8765/v1/chat/completions")!, model: String = "mlx-community/Qwen3.5-4B-MLX-4bit", timeout: TimeInterval = 3, transport: HTTPTransport = URLSessionTransport())
  public func verdict(for c: Candidate) async throws -> Verdict   // throws on network/timeout/parse
}
public struct RuleJudge: Judge { public init() }                   // deterministic copy per watcher, source .rules
public struct FallbackJudge: Judge { public init(primary: LocalModelJudge, fallback: RuleJudge = RuleJudge()) }
public protocol HTTPTransport: Sendable { func post(_ url: URL, body: Data, timeout: TimeInterval) async throws -> Data }
public enum JudgePrompt { public static let system: String; public static func user(_ c: Candidate) -> String }
```
Prompt: the POC 1 v2 framing, verbatim intent: show a card when there is a concrete helpful action the user would likely approve (freeing wasted resources, unblocking, preventing embarrassment, saving repeated work); not when nothing is wrong, the thing is in use, or it would get in the way; answer ONLY JSON `{"show": bool, "value": 1-5, "title": "<=8 words", "body": "<=24 words", "action": "<=3 words"}`; three examples (idle process → show; music app using memory while playing → don't; failed upload → show). Request body: `{"model", "messages", "temperature": 0, "max_tokens": 160, "chat_template_kwargs": {"enable_thinking": false}}`. Parse the first `{…}` in `choices[0].message.content`. `RuleJudge` copy: screenshots → title "Tidy <N> screenshots", body "Move them into Pictures › Screenshots by month. Undo any time.", action "Tidy up"; bin → "Your Bin is holding <X> GB", "<n> big items make up <Y> GB. Emptying can't be undone.", "Empty <n>"; tabs → "<N> tabs about <topic>", "Turn them into one comparison table in Notes?", "Make the note". Rule verdicts always `show: true, value: 3`.
`scripts/judge-server.sh start|stop|status`: venv at `~/Library/Application Support/Sparehand/judge-venv` (`uv venv --python 3.12`, `uv pip install mlx-lm==0.32.2`), runs `mlx_lm.server --model <model> --host 127.0.0.1 --port 8765 --chat-template-args '{"enable_thinking":false}'` in the background, pid file next to the venv.
- [ ] Tests with a fake `HTTPTransport`: `parsesModelVerdict`, `fallsBackWhenServerDown` (transport throws → `.rules`), `fallsBackOnBadJSON`, `requestDisablesThinking` (captured body has `chat_template_kwargs.enable_thinking == false`, `temperature == 0`), `ruleCopyPerWatcher`. FAIL → implement → PASS.
- [ ] Manual: `scripts/judge-server.sh start`, then `swift run sparehand judge --sample screenshots` (CLI stub added in Task 11; until then run the test target's `liveServerSmoke` test, skipped unless `SPAREHAND_LIVE_JUDGE=1`) → prints a model verdict in < 2 s after warm-up. Commit `feat: local judge with rules fallback`.

### Task 7: Browser tabs, topic clustering and the tabs watcher

**Files:** Create `Sources/SparehandCore/Apps/AppleScript.swift` (finish), `Sources/SparehandCore/Apps/BrowserTabs.swift`, `Sources/SparehandCore/Watchers/TabsWatcher.swift`; Tests `BrowserTabsTests.swift`, `TabsWatcherTests.swift`.

**Interfaces — Produces:**
```swift
public struct OSAScriptRunner: ScriptRunner { public init() }      // NSAppleScript on a dedicated thread; throws ScriptError(code, message)
public struct ScriptError: Error, Sendable { public var code: Int; public var message: String }   // -1743 = Automation denied
public enum AppleScriptText { public static func quoted(_ s: String) -> String }               // escapes \ and "
public enum BrowserTabs {
  public static let chromeFamily = ["Google Chrome", "Arc", "Dia", "Brave Browser", "Microsoft Edge"]
  public static func listScript(app: String) -> String      // returns "title\u{1F}url\u{1E}" records
  public static func safariListScript() -> String
  public static func parse(_ output: String, browser: String) -> [Tab]
  public static func all(runner: ScriptRunner, running: Set<String>) async -> [Tab]   // only running browsers; errors → []
}
public struct TopicClusterer: Sendable {
  public init(threshold: Double = 0.62)
  public func clusters(_ titles: [String]) -> [[Int]]        // NLEmbedding.sentenceEmbedding(for: .english); greedy average-link
  public func topic(of titles: [String]) -> String           // most frequent non-stopword bigram/unigram across titles, Title Case
}
public struct TabsWatcher: Watcher { public init(minTabs: Int = 5, minAge: TimeInterval = 6 * 3600) }
```
Rules: collect tabs from running browsers (running set from `NSWorkspace` bundle names, passed in by the Engine); record first-seen per URL in the Store; cluster titles; for each cluster of ≥ `minTabs` tabs whose earliest first-seen is older than `minAge`, one candidate `.tabsToNote(topic:tabs:)`, summary `"<N> open tabs about <topic>, open since <weekday>."`, evidence = first 3 titles. Fingerprint keys = sorted URLs. `minAge` is overridable via store setting `tabs.minAgeSeconds` (demo sets 60).
- [ ] Tests: `parsesChromeRecords`, `parsesSafariRecords`, `quotesAppleScript`, `deniedAutomationYieldsNoTabs` (runner throws code -1743 → `[]`), `clustersMBAvsKubernetes` (the POC 1 titles: 1,3,5 vs 2,4), `clustersGoaVsReact`, `topicNamesCluster` (`["Best standing desks 2026", "Standing desk buying guide", …]` → contains "Standing Desk"), `respectsMinAge`, `minAgeFromSetting`. FAIL → implement → PASS → commit `feat: browser tabs and tabs watcher`.

### Task 8: Claude Code job (prompt, stream parsing, table extraction)

**Files:** Create `Sources/SparehandCore/Jobs/ClaudeJob.swift`, `Tests/SparehandCoreTests/Fixtures/claude-stream.jsonl`, `Tests/SparehandCoreTests/ClaudeJobTests.swift`.

**Interfaces — Produces:**
```swift
public struct ClaudeJob: Sendable {
  public static func prompt(topic: String, tabs: [Tab]) -> String
  public static func arguments(prompt: String) -> [String]
  // ["-p", prompt, "--output-format", "stream-json", "--verbose", "--allowedTools", "WebFetch", "--max-turns", "12"]
  public static func progressLine(_ jsonLine: String) -> String?   // human line for the watchable Terminal, or nil
  public static func finalText(_ jsonLines: [String]) throws -> String   // from the "result" event; throws ClaudeJobError
  public static func extractTable(_ text: String) throws -> String       // first <table>…</table>
  public static func sanitize(_ html: String) -> String                  // keep table, thead, tbody, tr, th, td, b, strong, i, em, a[href http(s)], br; drop everything else incl. attributes except href
  public static func locate() -> URL?                                    // `claude` on PATH, ~/.local/bin/claude, /opt/homebrew/bin/claude
}
public enum ClaudeJobError: Error, Equatable { case notInstalled, failed(String), noTable }
```
Prompt (exact intent): "Read these <N> pages with WebFetch and compare the products/options they describe for someone deciding about <topic>. Reply with ONLY one HTML <table>: first column the option name linked to its page, then 4-6 columns chosen for this decision (for example price, size, key feature, warranty), one row per option. Use 'not listed' when a page doesn't say. No text outside the table." followed by the numbered URLs.
`progressLine`: `assistant` tool_use WebFetch → `"Reading <host>…"`; assistant text → first 80 chars; `result` success → `"Done. Table ready."`; error result → `"Claude stopped: <message>"`.
- [ ] Tests: `argumentsRestrictTools`, `progressFromFixture` (fixture: system init, 2 WebFetch tool_use, assistant text, result), `finalTextFromResult`, `errorResultThrows`, `extractsTable`, `noTableThrows`, `sanitizeStripsScriptsAndAttributes` (`<table onclick=x><tr><td><script>…</script><a href="javascript:x">y</a></td></tr></table>` → no `script`, no `onclick`, no `javascript:`). FAIL → implement → PASS → commit `feat: claude job parsing and sanitising`.

### Task 9: Terminal and Notes drivers

**Files:** Create `Sources/SparehandCore/Apps/Terminal.swift`, `Sources/SparehandCore/Apps/Notes.swift`; Test `Tests/SparehandCoreTests/AppDriverTests.swift`.

**Interfaces — Produces:**
```swift
public struct TerminalLauncher: Sendable {
  public init(runner: ScriptRunner)
  public func open(command: String, title: String) async throws -> Int      // returns the new window's id
  public func setBounds(windowID: Int, _ rect: CGRect) async throws
  public func close(windowID: Int) async throws
  public static func openScript(command: String, title: String) -> String  // do script in a NEW window; set custom title; return id of that window
}
public struct NotesWriter: Sendable {
  public init(runner: ScriptRunner)
  public func create(title: String, html: String) async throws -> String    // returns note id
  public func delete(noteID: String) async throws                           // used by undo
  public func show(noteID: String, ifNoUserWindows windowsBefore: Int) async throws -> Int?   // returns window id only if Notes had 0 windows before; else nil (Review Focus 5)
  public static func createScript(title: String, html: String) -> String    // body = "<h1>title</h1>" + html, in the default account's "Notes" folder
}
```
- [ ] Tests (fake runner capturing scripts): `terminalScriptUsesNewWindow` (contains `do script` and not `in window 1`), `scriptsQuoteInput`, `notesCreateScriptHasTitleAndTable`, `notesSkipsShowWhenUserWindowsOpen` (windowsBefore 2 → nil, no `bounds` script sent). FAIL → implement → PASS.
- [ ] Manual (with you present, approves Automation prompts): `swift run sparehand claude-run --dry` opens a Terminal window and prints its id; `swift run sparehand note-test` creates and deletes a test note. Commit `feat: terminal and notes drivers`.

### Task 10: Sparehand's own screen and the live viewer

**Files:** Create `Sources/CVirtualDisplay/include/CVirtualDisplay.h`, `Sources/CVirtualDisplay/shim.m`, `Sources/SparehandApp/AgentScreen/AgentScreen.swift`, `Sources/SparehandApp/AgentScreen/LiveViewer.swift`, `Sources/SparehandApp/AgentScreen/LiveViews.swift`.

**Interfaces — Produces:**
```c
// CVirtualDisplay.h
typedef struct { uint32_t displayID; void *handle; } SHVirtualDisplay;
SHVirtualDisplay SHCreateVirtualDisplay(uint32_t width, uint32_t height, uint32_t serial, const char *name); // displayID 0 on failure
void SHDestroyVirtualDisplay(SHVirtualDisplay d);
```
```swift
@MainActor final class AgentScreen {
  func start() throws -> CGRect               // 1920×1080, serial = UInt32.random(in: 1..<UInt32.max); returns its bounds
  func stop()
  var bounds: CGRect? { get }
  func workArea() -> CGRect                   // bounds inset 120 pt horizontally, 90 pt vertically
}
@MainActor final class LiveViewer {
  init(screen: AgentScreen)
  func start(windowIDs: [CGWindowID]) async throws      // SCStream filter includingWindows; 30 fps; background #F4F2EE
  func add(windowID: CGWindowID) async throws           // updateContentFilter
  func stop() async
  var steps: [LiveStep]; var status: String             // published for the views
}
struct LiveStep: Identifiable { let id: Int; let text: String; var state: State; enum State { case done, current, pending } }
```
Views follow canvas screens 2 and 3 (light theme): PiP `NSPanel` 480 wide, bottom-right of the main screen, non-activating, floating; "Watch full screen" opens a separate window and calls `toggleFullScreen` so it gets its own Space; Pause/Stop buttons call back into the Engine (Task 11).
- [ ] Manual self-test `Sparehand.app --agent-screen-selftest` (added here): creates the screen, opens a TextEdit document by name onto it, streams only that window into the PiP for 15 s, closes the document, stops. Expected: the PiP shows only the TextEdit window on a `#F4F2EE` backdrop; your own windows never move (compare `osascript` bounds before/after, as in POC 3). Commit `feat: agent screen and live viewer`.

### Task 11: Engine and CLI

**Files:** Create `Sources/SparehandCore/Engine/Engine.swift`, `Sources/sparehand/main.swift`; Test `Tests/SparehandCoreTests/EngineTests.swift`.

**Interfaces — Consumes:** Tasks 2–9. **Produces:**
```swift
public protocol QuietRules: Sendable { func isQuiet() -> Bool }      // app supplies: full screen or call app frontmost
public protocol JobRunner: Sendable {                                // app supplies the watchable runner (Task 12); CLI supplies a headless one
  func runTabsToNote(tap: Tap) async throws -> String                // returns note id
}
public actor Engine {
  public init(env: Environment, watchers: [any Watcher], judge: any Judge, quiet: any QuietRules, jobs: any JobRunner, minGap: TimeInterval = 600)
  public func tick(runningBrowsers: Set<String>) async -> [Tap]      // new pending taps to show now
  public func approve(_ tapID: String) async -> Tap                  // executes the plan; state done/failed
  public func dismiss(_ tapID: String, snooze: TimeInterval = 86_400) async
  public func undo(_ tapID: String) async -> Tap                     // moveFiles → FileMover.undo; tabsToNote → NotesWriter(runner: env.scripts).delete(noteID: tap.resultRef)
  public func feed() async -> (pending: [Tap], done: [Tap])
}
```
Rules: `approve` stores the note id returned by `JobRunner` in `tap.resultRef`. A candidate whose fingerprint already has a tap in any state except `undone` is not re-tapped (dismissed ones return after `snooze`); verdict `show == false` → stored as `dismissed` silently; at most one new tap per watcher per `minGap`; when `quiet.isQuiet()` taps are created but returned from `feed()` only, not from `tick`. `.deletePermanently` runs `FileManager.removeItem` per URL, collecting failures into `note`.
CLI commands: `sparehand scan` (prints candidates + verdicts, no actions), `sparehand judge --sample <watcher>`, `sparehand claude-run --job <tapID>` (runs Claude with `ClaudeJob.arguments`, prints `progressLine`s, writes final table to `~/Library/Application Support/Sparehand/jobs/<tapID>.html`, exit 0/1), `sparehand undo <tapID>`, `sparehand demo-seed` (Task 13).
- [ ] Tests with fakes (watcher returning fixed candidates, fixed judge, fake clock, fake quiet, fake jobs): `dedupsByFingerprint`, `respectsMinGap`, `quietHoldsTapsInFeed`, `hiddenVerdictNotShown`, `approveMovesFilesAndUndoRestores`, `dismissSnoozes`, `failedJobMarksFailed`. FAIL → implement → PASS → commit `feat: engine and cli`.

### Task 12: Menu-bar app, tap card, feed, onboarding, watchable job runner

**Files:** Create `Sources/SparehandApp/SparehandApp.swift`, `UI/Theme.swift`, `UI/TapPanel.swift`, `UI/TapCard.swift`, `UI/FeedView.swift`, `UI/OnboardingView.swift`, `AgentScreen/WatchableJobRunner.swift`, `Resources/Info.plist`.

**Interfaces — Consumes:** Engine (Task 11), AgentScreen/LiveViewer (Task 10), TerminalLauncher/NotesWriter (Task 9). **Produces:** `final class WatchableJobRunner: JobRunner` that: starts AgentScreen → opens Terminal on it running `sparehand claude-run --job <id>` (path of the bundled CLI) → streams that window in the PiP with steps ["Opened Terminal on Sparehand's screen", "Claude is reading the pages", "Making the table", "Putting it in Notes"] → waits for the job file → `NotesWriter.create` → shows Notes on the agent screen only if Notes had no windows → adds it to the stream → holds 4 s → closes its own Terminal window → stops the screen. Pause = suspend the Claude process (SIGSTOP/SIGCONT); Stop = terminate it and mark the tap failed ("Stopped by you").
UI per canvas screens 1, 4, 6 (light theme, Global Constraints colours): tap card in a non-activating `NSPanel` top-right (title, body, evidence rows, primary action, "Not now", "Details" expands evidence, footer "Decided on this Mac" + "Can't be undone" for `.deletePermanently`); a second confirm alert before `.deletePermanently` runs ("Empty <n> items? This can't be undone."); `MenuBarExtra` feed: pending taps with action + Not now, "Done today" with Undo for reversible ones, "Pause 1 hour"; onboarding window on first launch listing Full Disk Access (check `BinAccess.canRead`), Screen Recording (`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`), Automation (triggered on first tabs scan) and the judge model (button runs `judge-server.sh start`, shows status). App ticks the Engine every 60 s and on FSEvents for Desktop and Bin.
- [ ] Manual: `scripts/bundle-app.sh && open dist/Sparehand.app`; with 25 test screenshots in a temp HOME (`SPAREHAND_HOME=/tmp/sh-home`, honoured by `Environment`) a card appears within 60 s; Approve empties the temp Desktop; Undo restores. Commit `feat: menu-bar app, tap card, feed, onboarding`.

### Task 13: Bundle, signing and demo seeding

**Files:** Create `scripts/bundle-app.sh`, `Sources/sparehand/DemoSeed.swift`.

- [ ] `scripts/bundle-app.sh`: `swift build -c release`, assemble `dist/Sparehand.app` (Info.plist, binary, bundled `sparehand` CLI and `judge-server.sh` in `Contents/Resources`), sign with identity `Sparehand Dev` if `security find-identity -p codesigning` lists it, else ad-hoc (print a warning that permissions reset on each build).
- [ ] `sparehand demo-seed --screenshots 120 --bin-gb 12 --tabs standing-desks`: writes 120 PNGs named `Screenshot YYYY-MM-DD at HH.MM.SS.png` spread over the last 5 months (simple generated images: coloured window shapes, no text) with creation dates set to match the names; creates 3 files of 6, 4 and 2 GB (`truncate`) and moves them to the Bin via Finder (`tell application "Finder" to delete`); opens 7 standing-desk review URLs (list kept in the source) in the default browser; sets `tabs.minAgeSeconds` to 60. Refuses to run unless the user name is `demo` or `--yes-this-is-a-demo-account` is passed.
- [ ] Manual: run in the Demo account → Desktop shows 120 screenshots, Bin ≈ 12 GB, 7 tabs open. Commit `feat: bundle script and demo seeding`.

### Task 14: End-to-end demo rehearsal (verification)

- [ ] In the Demo macOS account (you create it and log in to Claude Code there): install the app, grant permissions, `demo-seed`, start the judge.
- [ ] Demo 1: screenshot tap appears → Approve → Desktop clear → Bin tap → confirm → Finder Bin empty, System Settings › Storage shows the drop → Undo screenshots → they return.
- [ ] Demo 2: after 60 s the tabs tap appears → Approve and watch → PiP shows Terminal with Claude reading the pages, then Notes with the table → swipe to full screen and back → open Notes yourself: the note is there; your own windows never moved.
- [ ] Record both with a screen recorder limited to Sparehand's windows and the relevant apps; note any rough edges as follow-ups. Commit fixes found during rehearsal with their tests.
