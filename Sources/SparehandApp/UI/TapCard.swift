import AppKit
import SparehandCore
import SwiftUI

/// The tap. Collapsed: what, the benefit, act. Expanded: what will happen, why now, the steps, examples, Never.
struct TapCard: View {
    let tap: Tap
    var expanded: Bool
    var onApprove: () -> Void
    var onDismiss: () -> Void
    var onNever: () -> Void
    var onToggle: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tap.verdict.title).font(Theme.heading(17)).foregroundStyle(Theme.ink).lineLimit(2)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 20, height: 20).background(Theme.surface, in: Circle())
                }
                .buttonStyle(.plain).help("Hide for now. It stays in the menu bar.")
            }
            if let b = tap.candidate.benefit, !b.isEmpty {
                Label(b, systemImage: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.working)
                    .labelStyle(TightLabel())
            }
            if expanded { details.transition(.opacity) }
            HStack(spacing: 8) {
                Button(tap.verdict.actionLabel, action: onApprove).buttonStyle(PillButton(fill: Theme.decide, text: .white))
                Button("Not now", action: onDismiss).buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                Spacer()
                Button(action: onToggle) {
                    HStack(spacing: 3) {
                        Text(expanded ? "Less" : "Details")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.body)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .light)
    }

    var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("WHAT HAPPENS", tap.verdict.body)
            row("WHY NOW", tap.candidate.why)
            if tap.candidate.steps.count > 1 {
                row("STEPS", tap.candidate.steps.enumerated().map { "\($0.offset + 1). " + WatchableRun.describe($0.element) }.joined(separator: "\n"))
            }
            if !tap.candidate.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FOR EXAMPLE").font(.system(size: 10, weight: .semibold)).kerning(0.5).foregroundStyle(Theme.muted)
                    ForEach(Array(tap.candidate.evidence.prefix(3).enumerated()), id: \.offset) { _, e in
                        Text(e.label).font(.system(size: 12)).foregroundStyle(Theme.body).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            HStack {
                Label(tap.candidate.isReversible ? "Undo any time" : "Can't be undone", systemImage: "arrow.uturn.backward")
                    .labelStyle(TightLabel()).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Never offer this", action: onNever).buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    func row(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .semibold)).kerning(0.5).foregroundStyle(Theme.muted)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.system(size: 10, weight: .bold)); configuration.title }
    }
}

/// The hand mark from the design canvas.
struct HandMark: View {
    var size: CGFloat
    var color: Color = Theme.decide
    var body: some View {
        Image(systemName: "hand.raised").font(.system(size: size, weight: .semibold)).foregroundStyle(color)
    }
}

/// A non-activating panel at the top right holding up to 3 cards, so a tap never steals focus from what the user is typing.
@MainActor
final class TapPanel {
    private let panel: NSPanel
    private weak var model: AppModel?
    private var taps: [Tap] = []
    private var expanded: Set<String> = []

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(_ new: [Tap]) {
        for t in new where !taps.contains(where: { $0.id == t.id }) { taps.append(t) }
        taps = Array(taps.prefix(3))
        layout(fade: true)
    }

    func remove(_ id: String) {
        taps.removeAll { $0.id == id }
        taps.isEmpty ? panel.orderOut(nil) : layout(fade: false)
    }

    func hide() { taps = []; panel.orderOut(nil) }

    func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        layout(fade: false)
    }

    private func layout(fade: Bool) {
        guard !taps.isEmpty else { panel.orderOut(nil); return }
        let stack = VStack(spacing: 10) {
            ForEach(taps) { tap in
                TapCard(tap: tap, expanded: self.expanded.contains(tap.id),
                        onApprove: { [weak self] in self?.model?.approve(tap) },
                        onDismiss: { [weak self] in self?.model?.dismiss(tap) },
                        onNever: { [weak self] in self?.model?.never(tap) },
                        onToggle: { [weak self] in self?.toggle(tap.id) },
                        onClose: { [weak self] in self?.remove(tap.id) })
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            }
        }
        .padding(16)
        let host = NSHostingView(rootView: stack)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.contentView = host
        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            let h = min(size.height, f.height)
            panel.setFrame(NSRect(x: f.maxX - size.width - 8, y: f.maxY - h, width: size.width, height: h), display: true)
        }
        if fade {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        } else {
            panel.orderFrontRegardless()
        }
    }
}
