import SwiftUI

/// The live picture of Sparehand's screen. `compact` is the picture-in-picture panel (canvas screen 2);
/// otherwise the full-screen view with a "what I'm doing" rail (canvas screen 3). Light theme.
struct LivePanelView: View {
    @ObservedObject var viewer: LiveViewer
    let compact: Bool

    var body: some View {
        Group {
            if compact { panel } else { full }
        }
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(viewer.needsYou ? Theme.decide : Theme.working).frame(width: 8, height: 8)
            Text(viewer.needsYou ? "Sparehand needs you" : "Sparehand is working on its own screen")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Spacer()
            if let i = viewer.steps.firstIndex(where: { $0.state == .current }) {
                Text("Step \(i + 1) of \(viewer.steps.count)").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewer.steps) { step in
                HStack(spacing: 8) {
                    switch step.state {
                    case .done: Text("✓").foregroundStyle(Theme.working)
                    case .current: Circle().strokeBorder(Theme.working, lineWidth: 2).frame(width: 12, height: 12)
                    case .pending: Circle().strokeBorder(Theme.pending, lineWidth: 2).frame(width: 12, height: 12)
                    }
                    Text(step.text)
                        .font(.system(size: 13, weight: step.state == .current ? .medium : .regular))
                        .foregroundStyle(step.state == .current ? Theme.ink : Theme.muted)
                }
            }
            Text(viewer.status).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
        }
    }

    private func buttons(full: Bool) -> some View {
        HStack(spacing: 8) {
            if !full {
                Button { viewer.watchFullScreen() } label: {
                    Label("Watch full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(PillButton(fill: Theme.well, text: Theme.ink))
            }
            Button("Pause") { viewer.onPause?() }.buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
            Spacer()
            Button("Stop") { viewer.onStop?() }.buttonStyle(PillButton(fill: Theme.decideSoft, text: Theme.decideDeep))
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            FrameView(viewer: viewer)
                .frame(height: 252)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            stepsList
            buttons(full: false)
        }
        .padding(14)
        .frame(width: 480)
        .background(Theme.card)
    }

    private var full: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Circle().fill(Theme.working).frame(width: 8, height: 8)
                    Text("Live · Sparehand's screen").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.working)
                    Text("Your desk is untouched. Swipe with three fingers to go back.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                FrameView(viewer: viewer).clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("WHAT I'M DOING").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                stepsList
                Spacer()
                buttons(full: true)
            }
            .padding(18)
            .frame(width: 340)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
        }
        .padding(28)
        .background(Theme.surface)
    }
}

struct FrameView: NSViewRepresentable {
    let viewer: LiveViewer

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer = viewer.makeLayer()
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct PillButton: ButtonStyle {
    var fill: Color
    var text: Color
    var border: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(fill, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(border ?? .clear))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
