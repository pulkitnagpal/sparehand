import AppKit

@main
enum SparehandMain {
    @MainActor static func main() {
        setvbuf(stdout, nil, _IONBF, 0)
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--agent-screen-selftest") {
            let test = AgentScreenSelfTest()
            app.delegate = test
            app.setActivationPolicy(.accessory)
            app.run()
            return
        }
        print("Sparehand: the menu-bar app arrives in Task 12.")
    }
}
