import Foundation
import SparehandCore

// sparehand: the command-line side of Sparehand. Same engine as the app, for testing the whole loop and seeding demos.
setvbuf(stdout, nil, _IONBF, 0)

let usage = """
    usage:
      sparehand look [--force]        look at the Mac once and print each step of the decision (creates a pending card)
      sparehand feed                  pending cards and what was done today
      sparehand approve <id>          run a card's plan, printing progress
      sparehand undo <id>             undo a done card
      sparehand dismiss <id>          Not now
      sparehand never <id>            Never for this (goes into memory)
      sparehand memory | skills       what Sparehand knows and has learned
      sparehand demo-seed <count>     put <count> realistic screenshots on the Desktop of $SPAREHAND_HOME (or this account)
    Set SPAREHAND_HOME to run against a test home folder.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func makeEngine() -> (Engine, Environment) {
    let store: Store
    do { store = try Store(path: Environment.supportDirectory.appendingPathComponent("sparehand-v1.sqlite")) }
    catch { fail("can't open the store: \(error)") }
    let env = Environment.live(store: store)
    let engine = Engine(env: env, senses: Senses(env: env), local: LocalModel(), claude: Claude.fromKeychain(), quiet: NeverQuiet())
    return (engine, env)
}

func show(_ t: Tap) {
    let badge = t.candidate.origin == .claude ? "asked Claude" : "noticed on your Mac"
    print("[\(t.id)] \(t.state.rawValue) · \(badge)")
    print("  \(t.verdict.title)")
    print("  \(t.verdict.body)")
    print("  why: \(t.candidate.why)")
    for e in t.candidate.evidence { print("  · \(e.label)  \(e.detail)") }
    print("  steps: " + t.candidate.steps.map { s in
        "\(s.tool)(" + (String(data: (try? JSONEncoder().encode(s.args)) ?? Data(), encoding: .utf8) ?? "") + ")"
    }.joined(separator: " → "))
    if let n = t.note { print("  result: \(n)") }
}

let args = Array(CommandLine.arguments.dropFirst())
let (engine, env) = makeEngine()

switch args.first {
case "look":
    await engine.sample()
    let t0 = Date()
    let r = await engine.look(force: args.contains("--force"))
    for s in r.steps { print("· " + s) }
    print(String(format: "(%.1fs, Claude $%.4f)", Date().timeIntervalSince(t0), r.claudeCostUSD))
    for t in r.taps { show(t) }
case "feed":
    let f = await engine.feed()
    print("pending: \(f.pending.count)"); f.pending.forEach(show)
    print("today: \(f.done.count)"); f.done.forEach(show)
case "approve":
    guard args.count > 1 else { fail(usage) }
    guard let t = await engine.approve(args[1], progress: { print("  … " + $0) }) else { fail("no such card") }
    show(t)
case "undo":
    guard args.count > 1, let t = await engine.undo(args[1]) else { fail("nothing to undo") }
    show(t)
case "dismiss":
    guard args.count > 1 else { fail(usage) }
    await engine.dismiss(args[1]); print("dismissed")
case "never":
    guard args.count > 1 else { fail(usage) }
    await engine.never(args[1]); print("won't offer that again")
case "memory":
    for m in await engine.memory() { print("- " + m) }
case "skills":
    for s in Skills.all(env.store) { print("- \(s.titleTemplate)  [\(s.steps.map(\.tool).joined(separator: ", "))]  min \(s.minCount)") }
case "run-plan":
    // Testing only: run a hand-written plan through the same tools, journal and undo as an approved card.
    guard args.count > 1, let obj = try? JSONSerialization.jsonObject(with: Data(args[1].utf8)) as? [Any] else { fail("run-plan '<json steps>'") }
    let steps = obj.compactMap { s -> ToolCall? in
        let v = JSONValue(any: s); guard let t = v["tool"]?.string else { return nil }; return ToolCall(tool: t, args: v["args"] ?? .object([:]))
    }
    let c = Candidate(id: "plan-\(Int(Date().timeIntervalSince1970))", origin: .claude, why: "manual test", steps: steps, noticedAt: Date())
    try? env.store.upsert(Tap(candidate: c, verdict: Verdict(title: "Manual plan", body: "", actionLabel: "Run", confidence: 5), createdAt: Date()))
    if let t = await engine.approve(c.id, progress: { print("  … " + $0) }) { show(t) }
case "demo-seed":
    DemoSeed.run(home: env.home, count: Int(args.dropFirst().first ?? "25") ?? 25)
default:
    print(usage)
}
