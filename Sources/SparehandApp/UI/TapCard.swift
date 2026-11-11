import AppKit
import SparehandCore
import SwiftUI

/// Canvas screen 1: what Sparehand noticed, the proof, one action, and a plain line on where it was decided.
struct TapCard: View {
    let tap: Tap
    var onApprove: () -> Void
    var onDismiss: () -> Void
    @State private var details = false

    var eyebrow: String {
        switch tap.candidate.watcher {
        case .screenshots: "SPAREHAND · DESKTOP"
        case .bin: "SPAREHAND · STORAGE"
        case .tabs: "SPAREHAND · TABS"
        }
    }

    var footer: String {
        let decided = tap.verdict.source == .model ? "Decided on this Mac." : "Decided by Sparehand's rules, on this Mac."
        switch tap.candidate.plan {
        case .deletePermanently: return decided + " Emptying can't be undone."
        case .moveFiles: return decided + " Undo any time."
        case .tabsToNote: return "Claude Code reads the pages after you approve. You can watch it work."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HandMark(size: 16).frame(width: 28, height: 28).background(Theme.decideSoft, in: RoundedRectangle(cornerRadius: 8))
                Text(eyebrow).font(.system(size: 12, weight: .semibold)).kerning(0.4).foregroundStyle(Theme.muted)
                Spacer()
                Text("now").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tap.verdict.title).font(Theme.heading(20)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text(tap.verdict.body).font(.system(size: 14)).foregroundStyle(Theme.body).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            if !tap.candidate.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(tap.candidate.evidence.enumerated()), id: \.offset) { _, e in
                        HStack {
                            Text(e.label).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(e.detail).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        .font(.system(size: 13)).foregroundStyle(Theme.body)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            }
            if details {
                Text(tap.candidate.summary).font(.system(size: 13)).foregroundStyle(Theme.body).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(tap.verdict.actionLabel, action: onApprove).buttonStyle(PillButton(fill: Theme.decide, text: .white))
                Button("Not now", action: onDismiss).buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                Spacer()
                Button(details ? "Less" : "Details") { details.toggle() }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.decide)
            }
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 11))
                Text(footer).fixedSize(horizontal: false, vertical: true)
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
                           onDismiss: { [weak self] in self?.model?.dismiss(tap) })
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
