import AppKit
import SparehandCore
import SwiftUI

/// The main window: what Sparehand found for you, what it did today, and what it has learned.
struct DashboardView: View {
    @ObservedObject var model: AppModel
    var section: Section { model.section }

    enum Section: String, CaseIterable, Identifiable {
        case forYou = "For you", today = "Today", learned = "Learned"
        var id: String { rawValue }
        var icon: String {
            switch self { case .forYou: "sparkles"; case .today: "checkmark.circle"; case .learned: "brain.head.profile" }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.section }, set: { model.section = $0 ?? .forYou })) {
                ForEach(Section.allCases) { s in
                    Label(s.rawValue, systemImage: s.icon)
                        .badge(s == .forYou ? model.pending.count : 0)
                        .tag(s)
                }
            }
            .navigationSplitViewColumnWidth(190)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            Group {
                switch section {
                case .forYou: ForYouView(model: model)
                case .today: TodayView(model: model)
                case .learned: LearnedView(model: model)
                }
            }
            .background(Theme.surface)
        }
        .navigationTitle("")
        .frame(minWidth: 920, minHeight: 600)
        .environment(\.colorScheme, .light)
        .task { await model.refreshFeed() }
    }

    var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SparehandLogo(size: 22)
                Text("Sparehand").font(Theme.heading(14)).foregroundStyle(Theme.ink)
            }
            HStack(spacing: 6) {
                Circle().fill(model.isPaused ? Theme.pending : Theme.working).frame(width: 7, height: 7)
                Text(model.isPaused ? "Paused" : "Watching").font(.system(size: 12)).foregroundStyle(Theme.body)
                Spacer()
                Button("Look now") { Task { await model.look(force: true) } }.controlSize(.small)
            }
        }
        .padding(12)
    }
}

// MARK: - For you

struct ForYouView: View {
    @ObservedObject var model: AppModel

    var items: [Tap] { model.acted + model.pending.filter { p in !model.acted.contains { $0.id == p.id } } }
    var selected: Tap? { items.first { $0.id == model.selectedOfferID } ?? items.first }

    var body: some View {
        if items.isEmpty {
            EmptyState(title: "Nothing to do right now", text: "Sparehand will let you know when something's worth it.")
        } else {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("For you").font(Theme.heading(22)).foregroundStyle(Theme.ink).padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 4)
                    Text("\(model.pending.count) \(model.pending.count == 1 ? "thing" : "things") worth doing")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.horizontal, 20).padding(.bottom, 14)
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(items) { tap in
                                OfferRow(tap: tap, phase: model.phases[tap.id] ?? .offer, selected: tap.id == selected?.id)
                                    .onTapGesture { model.selectedOfferID = tap.id }
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .frame(width: 330)
                Divider().overlay(Theme.hairline)
                if let tap = selected {
                    OfferDetail(model: model, tap: tap, phase: model.phases[tap.id] ?? .offer).id(tap.id)
                } else {
                    Spacer()
                }
            }
        }
    }
}

struct OfferRow: View {
    let tap: Tap
    let phase: CardPhase
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tap.verdict.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            switch phase {
            case .working(let line):
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(line).lineLimit(1) }
                    .font(.system(size: 12)).foregroundStyle(Theme.body)
            default:
                if let b = tap.candidate.benefit {
                    Label(b, systemImage: "arrow.up.right").labelStyle(TightLabel())
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.working)
                }
            }
            Text(tap.candidate.why).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.card : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.decide.opacity(0.45) : Theme.hairline))
        .contentShape(Rectangle())
    }
}

struct OfferDetail: View {
    @ObservedObject var model: AppModel
    let tap: Tap
    let phase: CardPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(tap.verdict.title).font(Theme.heading(26)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    if let b = tap.candidate.benefit {
                        Label(b, systemImage: "arrow.up.right").labelStyle(TightLabel())
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.working)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.workingSoft, in: Capsule())
                    }
                    block("WHAT HAPPENS") { Text(tap.verdict.body) }
                    block("WHY NOW") { Text(tap.candidate.why) }
                    block("STEPS") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(tap.candidate.steps.enumerated()), id: \.offset) { i, s in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                        .frame(width: 18, height: 18).background(Theme.ink.opacity(0.75), in: Circle())
                                    Text(WatchableRun.describe(s))
                                }
                            }
                        }
                    }
                    if !tap.candidate.evidence.isEmpty {
                        block("FOR EXAMPLE") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(tap.candidate.evidence.prefix(3).enumerated()), id: \.offset) { _, e in
                                    Text(e.label).lineLimit(1).truncationMode(.middle)
                                }
                            }
                        }
                    }
                    Label(tap.candidate.isReversible ? "You can undo this any time." : "This can't be undone.", systemImage: "arrow.uturn.backward")
                        .labelStyle(TightLabel()).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Theme.hairline)
            actions.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .background(Theme.card)
    }

    @ViewBuilder var actions: some View {
        switch phase {
        case .working(let line):
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text(line).font(.system(size: 13.5)).foregroundStyle(Theme.body).monospacedDigit() }
        case .done(let note):
            HStack { Label(note, systemImage: "checkmark.circle.fill").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.working); Spacer()
                Button("Undo") { model.undo(tap) } }
        case .failed(let note):
            Label(note, systemImage: "exclamationmark.circle.fill").font(.system(size: 13.5)).foregroundStyle(Theme.decide)
        default:
            HStack(spacing: 10) {
                Button(tap.verdict.actionLabel) { model.approve(tap) }.buttonStyle(PillButton(fill: Theme.decide, text: .white)).keyboardShortcut(.defaultAction)
                Button("Not now") { model.dismiss(tap) }.buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                Spacer()
                Button("Never offer this") { model.never(tap) }.buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            }
        }
    }

    func block<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10.5, weight: .semibold)).kerning(0.6).foregroundStyle(Theme.muted)
            content().font(.system(size: 14)).foregroundStyle(Theme.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Today and Learned

struct TodayView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if model.done.isEmpty {
            EmptyState(title: "Nothing done yet today", text: "What Sparehand does shows up here, each with Undo.")
        } else {
            List {
                ForEach(model.done) { tap in
                    HStack(spacing: 12) {
                        Image(systemName: tap.state == .undone ? "arrow.uturn.backward.circle" : tap.state == .failed ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .font(.system(size: 18)).foregroundStyle(tap.state == .failed ? Theme.decide : tap.state == .undone ? Theme.muted : Theme.working)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tap.verdict.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ink)
                            if let n = tap.note { Text(n).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1) }
                        }
                        Spacer()
                        Text((tap.finishedAt ?? tap.createdAt).formatted(date: .omitted, time: .shortened)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        if tap.state == .done && tap.candidate.isReversible { Button("Undo") { model.undo(tap) } }
                    }
                    .padding(.vertical, 6)
                }
            }
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top) { header("Today", "Everything Sparehand did, with Undo.") }
        }
    }
}

struct LearnedView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let skills = Skills.all(model.store)
        let memory = model.memoryLines
        if skills.isEmpty && memory.isEmpty {
            EmptyState(title: "Nothing learned yet", text: "Approve something once and Sparehand handles the repeat.")
        } else {
            List {
                if !skills.isEmpty {
                    Section("Handles on its own now") {
                        ForEach(skills, id: \.id) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.titleTemplate.replacingOccurrences(of: "{count}", with: "new")).font(.system(size: 13.5, weight: .medium))
                                Text("Learned \(s.learnedAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if !memory.isEmpty {
                    Section("What it knows about you") {
                        ForEach(memory, id: \.self) { Text($0).font(.system(size: 13)) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top) { header("Learned", "What Sparehand now handles on its own, and what it knows you don't want.") }
        }
    }
}

func header(_ title: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(Theme.heading(22)).foregroundStyle(Theme.ink)
        Text(text).font(.system(size: 13)).foregroundStyle(Theme.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
    .background(Theme.surface)
}

struct EmptyState: View {
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            SparehandLogo(size: 56).opacity(0.9)
            Text(title).font(Theme.heading(18)).foregroundStyle(Theme.ink)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
