import AppKit
import SparehandCore
import SwiftUI

/// Where a card is in its life. A card never vanishes on click: it changes state in place.
enum CardPhase: Equatable {
    case offer
    case working(String)
    case done(String)
    case failed(String)
    case undone(String)
}

/// The tap. Offer: what, the benefit, act. Then working → done (with Undo) or failed, in the same card.
struct TapCard: View {
    let tap: Tap
    var phase: CardPhase
    var expanded: Bool
    var onApprove: () -> Void
    var onDismiss: () -> Void
    var onNever: () -> Void
    var onToggle: () -> Void
    var onClose: () -> Void
    var onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let icon = headIcon {
                    Image(systemName: icon.0).font(.system(size: 13, weight: .bold)).foregroundStyle(icon.1)
                }
                Text(tap.verdict.title).font(Theme.heading(17)).foregroundStyle(Theme.ink).lineLimit(2)
                Spacer(minLength: 8)
                if !isWorking { closeButton }
            }
            switch phase {
            case .offer:
                if let b = tap.candidate.benefit, !b.isEmpty {
                    Label(b, systemImage: "arrow.up.right").labelStyle(TightLabel())
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.working)
                }
                if expanded { details }
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
            case .working(let line):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(line).font(.system(size: 13)).foregroundStyle(Theme.body).lineLimit(1).monospacedDigit()
                }
            case .done(let note):
                Text(note).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.working).lineLimit(2)
                if tap.candidate.isReversible {
                    Button("Undo", action: onUndo).buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                }
            case .failed(let note):
                Text(note).font(.system(size: 13)).foregroundStyle(Theme.decide).lineLimit(3)
                Button("OK", action: onClose).buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
            case .undone(let note):
                Text(note).font(.system(size: 13)).foregroundStyle(Theme.body).lineLimit(2)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.2), value: phase)
        .environment(\.colorScheme, .light)
    }

    var isWorking: Bool { if case .working = phase { return true }; return false }

    var headIcon: (String, Color)? {
        switch phase {
        case .done: ("checkmark.circle.fill", Theme.working)
        case .failed: ("exclamationmark.circle.fill", Theme.decide)
        case .undone: ("arrow.uturn.backward.circle.fill", Theme.muted)
        default: nil
        }
    }

    var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                .frame(width: 20, height: 20).background(Theme.surface, in: Circle())
        }
        .buttonStyle(.plain).help("Hide. It stays in the menu bar.")
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

/// The card stack's state: which cards are up, what phase each is in, which are expanded.
@MainActor
final class CardStack: ObservableObject {
    @Published var taps: [Tap] = []
    @Published var phases: [String: CardPhase] = [:]
    @Published var expanded: Set<String> = []
}

struct CardStackView: View {
    @ObservedObject var stack: CardStack
    weak var model: AppModel?
    let panel: TapPanel

    var body: some View {
        VStack(spacing: 10) {
            ForEach(stack.taps) { tap in
                TapCard(tap: tap, phase: stack.phases[tap.id] ?? .offer, expanded: stack.expanded.contains(tap.id),
                        onApprove: { model?.approve(tap) },
                        onDismiss: { model?.dismiss(tap) },
                        onNever: { model?.never(tap) },
                        onToggle: { panel.toggle(tap.id) },
                        onClose: { panel.remove(tap.id) },
                        onUndo: { model?.undo(tap) })
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        .fixedSize()
    }
}

/// A non-activating panel at the top right holding up to 3 cards, so a tap never steals focus from what the user is typing.
@MainActor
final class TapPanel {
    private let panel: NSPanel
    private weak var model: AppModel?
    private let stack = CardStack()
    private var removals: [String: Task<Void, Never>] = [:]
    private var host: NSHostingView<CardStackView>?

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 392, height: 220),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// New offers join the stack (at most 3 offers waiting at once).
    func show(_ new: [Tap]) {
        for t in new where !stack.taps.contains(where: { $0.id == t.id }) && stack.taps.count < 3 {
            stack.taps.append(t)
            stack.phases[t.id] = .offer
        }
        relayout(fade: true)
    }

    /// Moves a card to a new phase, adding it back if it was hidden (for example Undo from the feed).
    func set(_ tap: Tap, _ phase: CardPhase) {
        removals[tap.id]?.cancel(); removals[tap.id] = nil
        if let i = stack.taps.firstIndex(where: { $0.id == tap.id }) { stack.taps[i] = tap } else { stack.taps.insert(tap, at: 0) }
        stack.expanded.remove(tap.id)
        stack.phases[tap.id] = phase
        relayout(fade: false)
    }

    func removeLater(_ id: String, after seconds: Double) {
        removals[id]?.cancel()
        removals[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.remove(id)
        }
    }

    func remove(_ id: String) {
        removals[id]?.cancel(); removals[id] = nil
        withAnimation(.easeOut(duration: 0.2)) {
            stack.taps.removeAll { $0.id == id }
        }
        stack.phases[id] = nil
        stack.expanded.remove(id)
        relayout(fade: false)
    }

    func hide() { stack.taps = []; panel.orderOut(nil) }

    func toggle(_ id: String) {
        if stack.expanded.contains(id) { stack.expanded.remove(id) } else { stack.expanded.insert(id) }
        relayout(fade: false)
    }

    private func relayout(fade: Bool) {
        guard !stack.taps.isEmpty else { panel.orderOut(nil); return }
        if host == nil {
            let h = NSHostingView(rootView: CardStackView(stack: stack, model: model, panel: self))
            host = h
            panel.contentView = h
        }
        // Let SwiftUI settle, then fit the panel to the stack.
        DispatchQueue.main.async { [self] in
            guard let host else { return }
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
            if let f = screen?.visibleFrame {
                let h = min(size.height, f.height)
                panel.setFrame(NSRect(x: f.maxX - size.width - 8, y: f.maxY - h, width: size.width, height: h), display: true)
            }
            if fade && !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
            } else {
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
        }
    }
}
