import AppKit
import SwiftUI

@main
enum SparehandMain {
    @MainActor static func main() {
        setvbuf(stdout, nil, _IONBF, 0)
        if let i = CommandLine.arguments.firstIndex(of: "--export-logo"), i + 1 < CommandLine.arguments.count {   // build tooling
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for s in [16, 32, 64, 128, 256, 512, 1024] { try? LogoExport.png(size: CGFloat(s), to: dir.appendingPathComponent("icon_\(s).png")) }
            try? LogoExport.png(size: 1024, to: dir.appendingPathComponent("logo_full.png"), padded: false)
            print("exported to \(dir.path)")
            return
        }
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
            FeedView(model: delegate.model, openOnboarding: { delegate.showOnboarding() }, openWindow: { delegate.showDashboard() })
        } label: {
            Image(nsImage: LogoExport.menuBarImage())
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var onboarding: NSWindow?
    private var dashboard: NSWindow?
    private var dashboardClose: NSObjectProtocol?

    var dashboardWindowNumber: Int? { dashboard?.windowNumber }
    var dashboardWindow: NSWindow? { dashboard }

    /// The main window. Sparehand shows in the Dock while it's open.
    func showDashboard() {
        if dashboard == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Sparehand"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: DashboardView(model: model))
            w.setFrameAutosaveName("SparehandMain")
            dashboard = w
            dashboardClose = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
            }
        }
        NSApp.setActivationPolicy(.regular)
        dashboard?.center()
        dashboard?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        if CommandLine.arguments.contains("--welcome") {   // demos: start from the Welcome screen, then look
            showOnboarding()
            return
        }
        if CommandLine.arguments.contains("--window") { showDashboard() }
        if let i = CommandLine.arguments.firstIndex(of: "--film"), i + 1 < CommandLine.arguments.count {   // filming the demo
            let director = FilmDirector(model: model, delegate: self, dir: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            Task { await director.run() }
            return
        }
        if CommandLine.arguments.contains("--look-now") {   // testing and demos: look once right away
            Task {
                try? await Task.sleep(for: .seconds(2))
                await model.look(force: true)
                if CommandLine.arguments.contains("--approve-first"), let t = model.pending.first {   // testing only
                    try? await Task.sleep(for: .seconds(2))
                    model.approve(t)
                }
                if CommandLine.arguments.contains("--approve-all") {   // filming: approve every card, the watched one last
                    let order = model.pending.sorted { a, b in
                        !a.candidate.steps.contains { WatchableRun.watched.contains($0.tool) } && b.candidate.steps.contains { WatchableRun.watched.contains($0.tool) }
                    }
                    print("[cards] " + order.map { "\($0.id)|\($0.verdict.title)|\($0.candidate.benefit ?? "")" }.joined(separator: " ;; "))
                    for t in order {
                        try? await Task.sleep(for: .seconds(2))
                        model.approve(t)
                        while model.busyTapID != nil { try? await Task.sleep(for: .milliseconds(200)) }
                    }
                    print("[all-done]")
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
                if let m = self?.model { Task { await m.look(force: true) } }   // first look right away
            })
            onboarding = w
        }
        onboarding?.center()
        if CommandLine.arguments.contains("--film"), let retina = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }), let w = onboarding {
            w.setFrameOrigin(NSPoint(x: retina.visibleFrame.midX - w.frame.width / 2, y: retina.visibleFrame.midY - w.frame.height / 2))
        }
        onboarding?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
