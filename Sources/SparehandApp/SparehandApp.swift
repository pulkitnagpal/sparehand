import AppKit
import SwiftUI

@main
enum SparehandMain {
    @MainActor static func main() {
        setvbuf(stdout, nil, _IONBF, 0)
        if CommandLine.arguments.contains("--agent-screen-selftest") {
            let app = NSApplication.shared
            let test = AgentScreenSelfTest()
            app.delegate = test
            app.setActivationPolicy(.accessory)
            app.run()
            return
        }
        SparehandApp.main()
    }
}

struct SparehandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            FeedView(model: delegate.model, openOnboarding: { delegate.showOnboarding() })
        } label: {
            Image(systemName: "hand.raised")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var onboarding: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        if CommandLine.arguments.contains("--look-now") {   // testing and demos: look once right away
            Task {
                try? await Task.sleep(for: .seconds(2))
                await model.look(force: true)
                if CommandLine.arguments.contains("--approve-first"), let t = model.pending.first {   // testing only
                    try? await Task.sleep(for: .seconds(2))
                    model.approve(t)
                }
            }
            return
        }
        if (try? model.store.setting("onboarded")) ?? nil == nil { showOnboarding() }
    }

    func showOnboarding() {
        if onboarding == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 640), styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Welcome to Sparehand"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(model: model) { [weak self] in
                try? self?.model.store.setSetting("onboarded", "1")
                self?.onboarding?.close()
            })
            onboarding = w
        }
        onboarding?.center()
        onboarding?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
