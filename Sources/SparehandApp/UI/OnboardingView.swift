import AppKit
import SparehandCore
import SwiftUI

/// Canvas screen 6: each permission, why, and its state. All optional.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var refresh = 0
    var onDone: () -> Void

    struct Permission: Identifiable {
        let id: String
        let name: String
        let why: String
        let granted: Bool
        let action: () -> Void
    }

    var permissions: [Permission] {
        _ = refresh
        return [
            Permission(id: "fda", name: "Full Disk Access",
                       why: "See how much the Bin holds, so it can tell you when it is worth emptying.",
                       granted: (try? FileManager.default.contentsOfDirectory(atPath: model.env.trash.path)) != nil,
                       action: { Self.open("Privacy_AllFiles") }),
            Permission(id: "screen", name: "Screen Recording",
                       why: "Show you Sparehand's own screen live while it works. It never records yours.",
                       granted: CGPreflightScreenCaptureAccess(),
                       action: { if !CGRequestScreenCaptureAccess() { Self.open("Privacy_ScreenCapture") } }),
            Permission(id: "automation", name: "Browsers, Terminal and Notes",
                       why: "Read open tab titles, and open Terminal and Notes on its own screen. macOS asks the first time each is used.",
                       granted: false,
                       action: { Self.open("Privacy_Automation") }),
        ]
    }

    static func open(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HandMark(size: 26, color: .white).frame(width: 48, height: 48).background(Theme.decide, in: RoundedRectangle(cornerRadius: 14))
                Text("A spare pair of hands for your Mac").font(Theme.heading(28)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text("Sparehand notices what could be done for you, asks first, then does it, often on its own screen so you can watch.")
                    .font(.system(size: 14)).foregroundStyle(Theme.body).fixedSize(horizontal: false, vertical: true)
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    bullet("Decides on your Mac with a small local model")
                    bullet("Never acts without your tap")
                    bullet("Open source: read every rule it follows")
                }
            }
            .padding(28).frame(width: 300).frame(maxHeight: .infinity, alignment: .top).background(Theme.well)

            VStack(alignment: .leading, spacing: 14) {
                Text("PERMISSIONS").font(.system(size: 12, weight: .semibold)).kerning(0.5).foregroundStyle(Theme.muted)
                Text("Give it only what you're comfortable with").font(Theme.heading(22)).foregroundStyle(Theme.ink)
                Text("Each permission lets Sparehand see a little more. Skip any and turn it on later from the menu bar.")
                    .font(.system(size: 14)).foregroundStyle(Theme.body)
                ForEach(permissions) { p in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text(p.why).font(.system(size: 13)).foregroundStyle(Theme.body).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if p.granted {
                            Text("✓ Allowed").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.working)
                        } else {
                            Button(p.id == "automation" ? "Settings" : "Allow", action: p.action)
                                .buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                        }
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
                }
                HStack {
                    Text(model.status).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Check again") { refresh += 1 }.buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                    Button("Continue", action: onDone).buttonStyle(PillButton(fill: Theme.decide, text: .white))
                }
                .padding(.top, 6)
            }
            .padding(32)
        }
        .frame(width: 820, height: 640)
        .background(Theme.card)
        .environment(\.colorScheme, .light)
    }

    func bullet(_ s: String) -> some View {
        HStack(spacing: 8) { Text("✓").foregroundStyle(Theme.working); Text(s) }.font(.system(size: 13)).foregroundStyle(Theme.body)
    }
}
