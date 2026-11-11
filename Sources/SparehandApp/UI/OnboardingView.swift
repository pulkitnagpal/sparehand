import AppKit
import SparehandCore
import SwiftUI

/// Welcome: what Sparehand is, then a short setup. Connecting Claude is the one required step; the rest is optional.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var refresh = 0
    @State private var key = ""
    @State private var connecting = false
    @State private var keyError = false
    var onDone: () -> Void

    struct Row: Identifiable {
        let id: String
        let name: String
        let why: String
        let done: Bool
        let button: String
        let action: () -> Void
    }

    var rows: [Row] {
        _ = refresh
        return [
            Row(id: "screen", name: "Screen Recording", why: "To show you Sparehand's own screen. Yours is never recorded.",
                done: CGPreflightScreenCaptureAccess(), button: "Allow",
                action: { if !CGRequestScreenCaptureAccess() { Self.open("Privacy_ScreenCapture") } }),
            Row(id: "apps", name: "Finder, Notes and your browser", why: "macOS asks the first time Sparehand uses each one.",
                done: false, button: "Settings", action: { Self.open("Privacy_Automation") }),
            Row(id: "fda", name: "Full Disk Access · optional", why: "To see how full the Bin is.",
                done: (try? FileManager.default.contentsOfDirectory(atPath: model.env.trash.path)) != nil, button: "Allow",
                action: { Self.open("Privacy_AllFiles") }),
        ]
    }

    static func open(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                SparehandLogo(size: 52)
                Text("A spare pair of hands for your Mac").font(Theme.heading(28)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text("Sparehand notices what's worth doing while you work, asks first, then does it.")
                    .font(.system(size: 14)).foregroundStyle(Theme.body).fixedSize(horizontal: false, vertical: true)
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    bullet("Never acts without your tap")
                    bullet("Undo anything it did")
                    bullet("Your files never leave your Mac")
                }
            }
            .padding(28).frame(width: 300).frame(maxHeight: .infinity, alignment: .top).background(Theme.well)

            VStack(alignment: .leading, spacing: 12) {
                Text("SET UP").font(.system(size: 12, weight: .semibold)).kerning(0.5).foregroundStyle(Theme.muted)
                Text("Two minutes, once").font(Theme.heading(22)).foregroundStyle(Theme.ink)

                // Connect Claude: the one required step.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Connect Claude").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        if model.claude != nil { done("Connected") }
                    }
                    Text("Your Anthropic API key. It stays in your Mac's Keychain.").font(.system(size: 13)).foregroundStyle(Theme.body)
                    if model.claude == nil {
                        HStack(spacing: 8) {
                            SecureField("sk-ant-…", text: $key).textFieldStyle(.roundedBorder).font(.system(size: 13))
                            Button(connecting ? "Checking…" : "Connect") {
                                connecting = true; keyError = false
                                Task { keyError = !(await model.connect(apiKey: key)); connecting = false; if !keyError { key = "" } }
                            }
                            .buttonStyle(PillButton(fill: Theme.decide, text: .white)).disabled(connecting || key.isEmpty)
                        }
                        if keyError { Text("That key didn't work. Check it and try again.").font(.system(size: 12)).foregroundStyle(Theme.decide) }
                        Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                            .font(.system(size: 12))
                    }
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.claude == nil ? Theme.decide.opacity(0.5) : Theme.hairline))

                ForEach(rows) { r in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text(r.why).font(.system(size: 13)).foregroundStyle(Theme.body).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if r.done { done("Allowed") } else {
                            Button(r.button, action: r.action).buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                        }
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
                }
                Spacer(minLength: 0)
                HStack {
                    Button("Check again") { refresh += 1 }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.body)
                    Spacer()
                    Button("Start Sparehand", action: onDone).buttonStyle(PillButton(fill: Theme.decide, text: .white))
                        .disabled(model.claude == nil)
                }
            }
            .padding(32)
        }
        .frame(width: 820, height: 640)
        .background(Theme.card)
        .environment(\.colorScheme, .light)
    }

    func done(_ s: String) -> some View {
        Label(s, systemImage: "checkmark").labelStyle(TightLabel()).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.working)
    }

    func bullet(_ s: String) -> some View {
        HStack(spacing: 8) { Text("✓").foregroundStyle(Theme.working); Text(s) }.font(.system(size: 13)).foregroundStyle(Theme.body)
    }
}
