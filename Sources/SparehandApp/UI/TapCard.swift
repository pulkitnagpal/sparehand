import AppKit
import SparehandCore
import SwiftUI

/// The tap: what Sparehand noticed and why, the proof, one action, and where it was decided.
struct TapCard: View {
    let tap: Tap
    var onApprove: () -> Void
    var onDismiss: () -> Void
    var onNever: () -> Void

    var local: Bool { tap.candidate.origin == .skill }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HandMark(size: 13).frame(width: 24, height: 24).background(Theme.decideSoft, in: RoundedRectangle(cornerRadius: 7))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: local ? "laptopcomputer" : "sparkle").font(.system(size: 9, weight: .bold))
                    Text(local ? "On your Mac" : "Asked Claude").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(local ? Theme.working : Theme.decide)
                .background((local ? Theme.working : Theme.decide).opacity(0.1), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(tap.verdict.title).font(Theme.heading(18)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text(tap.verdict.body).font(.system(size: 13.5)).foregroundStyle(Theme.body).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Label(tap.candidate.why, systemImage: "eye")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            HStack(spacing: 8) {
                Button(tap.verdict.actionLabel, action: onApprove).buttonStyle(PillButton(fill: Theme.decide, text: .white))
                Button("Not now", action: onDismiss).buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                Spacer()
                Button("Never", action: onNever).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .light)
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

    private func layout(fade: Bool) {
        guard !taps.isEmpty else { panel.orderOut(nil); return }
        let stack = VStack(spacing: 10) {
            ForEach(taps) { tap in
                TapCard(tap: tap, onApprove: { [weak self] in self?.model?.approve(tap) },
                        onDismiss: { [weak self] in self?.model?.dismiss(tap) },
                        onNever: { [weak self] in self?.model?.never(tap) })
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            }
        }
        .padding(16)
        let host = NSHostingView(rootView: stack)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.contentView = host
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.maxX - size.width - 8, y: f.maxY - size.height, width: size.width, height: size.height), display: true)
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
