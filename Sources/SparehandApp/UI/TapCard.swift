import AppKit
import SparehandCore
import SwiftUI

/// The tap: what Sparehand noticed and why, the proof, one action, and where it was decided.
struct TapCard: View {
    let tap: Tap
    var onApprove: () -> Void
    var onDismiss: () -> Void
    var onNever: () -> Void
    @State private var details = false

    var local: Bool { tap.candidate.origin == .skill }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HandMark(size: 16).frame(width: 28, height: 28).background(Theme.decideSoft, in: RoundedRectangle(cornerRadius: 8))
                Text("SPAREHAND").font(.system(size: 12, weight: .semibold)).kerning(0.4).foregroundStyle(Theme.muted)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: local ? "laptopcomputer" : "sparkle").font(.system(size: 10, weight: .semibold))
                    Text(local ? "Noticed on your Mac" : "Asked Claude").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(local ? Theme.working : Theme.decide)
                .background((local ? Theme.working : Theme.decide).opacity(0.1), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tap.verdict.title).font(Theme.heading(20)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text(tap.verdict.body).font(.system(size: 14)).foregroundStyle(Theme.body).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "eye").font(.system(size: 11)).padding(.top, 2)
                Text("Why I noticed: " + tap.candidate.why).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5)).foregroundStyle(Theme.body)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            if details {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(tap.candidate.steps.enumerated()), id: \.offset) { i, s in
                        Text("\(i + 1). " + WatchableRun.describe(s)).font(.system(size: 12.5)).foregroundStyle(Theme.body)
                    }
                    ForEach(Array(tap.candidate.evidence.enumerated()), id: \.offset) { _, e in
                        Text("\(e.label) · \(e.detail)").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            HStack(spacing: 8) {
                Button(tap.verdict.actionLabel, action: onApprove).buttonStyle(PillButton(fill: Theme.decide, text: .white))
                Button("Not now", action: onDismiss).buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                Spacer()
                Button(details ? "Less" : "Steps") { details.toggle() }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.decide)
                Button("Never", action: onNever).buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 11))
                Text(local ? "Runs entirely on this Mac. Undo any time." : "Sparehand does every step on this Mac. Undo any time.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .padding(18)
        .frame(width: 404)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
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

/// A non-activating panel at the top right, so a tap never steals focus from what the user is typing.
@MainActor
final class TapPanel {
    private let panel: NSPanel
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 404, height: 300),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(_ tap: Tap) {
        let card = TapCard(tap: tap, onApprove: { [weak self] in self?.model?.approve(tap) },
                           onDismiss: { [weak self] in self?.model?.dismiss(tap) },
                           onNever: { [weak self] in self?.model?.never(tap) })
        let host = NSHostingView(rootView: card)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.contentView = host
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.maxX - size.width - 24, y: f.maxY - size.height - 16, width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
    }

    func hide() { panel.orderOut(nil) }
}
