import AppKit
import SparehandCore

/// `Sparehand --agent-screen-selftest`: Sparehand's screen + live viewer on a scratch TextEdit document.
@MainActor
final class AgentScreenSelfTest: NSObject, NSApplicationDelegate {
    let screen = AgentScreen()
    lazy var viewer = LiveViewer(screen: screen)
    let scripts = OSAScriptRunner()

    func applicationDidFinishLaunching(_ n: Notification) {
        Task { await run(); NSApp.terminate(nil) }
    }

    func userTextEditBounds() async -> String {
        (try? await scripts.run("tell application \"TextEdit\" to if running then get bounds of every window")) ?? "-"
    }

    func run() async {
        let before = await userTextEditBounds()
        do {
            let b = try await screen.start()
            print("agent screen at \(b)")
            let area = screen.workArea()
            let name = try await scripts.run("""
                tell application "TextEdit"
                  set d to make new document with properties {text:""}
                  set n to name of d
                  delay 0.5
                  set bounds of (first window whose name is n) to {\(Int(area.minX)), \(Int(area.minY)), \(Int(area.maxX)), \(Int(area.maxY))}
                  return n
                end tell
                """)
            try await Task.sleep(for: .milliseconds(600))
            guard let wid = WindowFinder.windowID(owner: "TextEdit", title: name, inside: b) else { print("FAILED: window not found"); return }
            viewer.setSteps(["Opened a scratch document on Sparehand's screen", "Typing", "Closing it"])
            try await viewer.start(windowIDs: [wid])
            viewer.advance(to: 1)
            var text = ""
            for line in ["Sparehand self-test.", "This window lives on Sparehand's own screen.", "Your windows never moved."] {
                text += line + "\n"
                _ = try await scripts.run("tell application \"TextEdit\" to set text of document \(AppleScriptText.quoted(name)) to \(AppleScriptText.quoted(text))")
                try await Task.sleep(for: .seconds(2))
            }
            viewer.advance(to: 2)
            try await Task.sleep(for: .seconds(6))
            _ = try await scripts.run("tell application \"TextEdit\" to close document \(AppleScriptText.quoted(name)) saving no")
            viewer.finishSteps()
            await viewer.stop()
            screen.stop()
        } catch {
            print("FAILED: \(error)")
            await viewer.stop()
            screen.stop()
        }
        try? await Task.sleep(for: .seconds(1.5))   // let the scratch window finish closing
        let after = await userTextEditBounds()
        print("your TextEdit windows before: \(before)")
        print("your TextEdit windows after:  \(after)")
        print(before == after ? "PASS: your windows did not move" : "CHECK: window bounds changed")
    }
}
