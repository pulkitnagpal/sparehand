import SparehandCore
import SwiftUI

/// Canvas screen 4: the menu-bar feed — waiting suggestions, today's done jobs with Undo.
struct FeedView: View {
    @ObservedObject var model: AppModel
    var openOnboarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    HandMark(size: 14, color: .white).frame(width: 26, height: 26).background(Theme.decide, in: RoundedRectangle(cornerRadius: 8))
                    Text("Sparehand").font(Theme.heading(17)).foregroundStyle(Theme.ink)
                    Spacer()
                    Circle().fill(model.isPaused ? Theme.pending : Theme.working).frame(width: 7, height: 7)
                    Text(model.isPaused ? "Paused" : "Watching quietly").font(.system(size: 12)).foregroundStyle(Theme.body)
                }
                Text(model.status).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    section("SUGGESTED · \(model.pending.count)")
                    if model.pending.isEmpty {
                        Text("Nothing right now. Sparehand will tap you when something's worth it.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    }
                    ForEach(model.pending) { tap in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(tap.verdict.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(tap.candidate.origin == .skill ? "on your Mac" : "asked Claude").font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                            Text(tap.verdict.body).font(.system(size: 13)).foregroundStyle(Theme.body).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                Button(tap.verdict.actionLabel) { model.approve(tap) }.buttonStyle(PillButton(fill: Theme.decide, text: .white))
                                Button("Not now") { model.dismiss(tap) }.buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                            }
                            .disabled(model.busyTapID != nil)
                        }
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
                    }

                    section("DONE TODAY").padding(.top, 8)
                    ForEach(model.done) { tap in
                        HStack(spacing: 10) {
                            Text(symbol(tap)).foregroundStyle(tap.state == .failed ? Theme.decide : Theme.working)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tap.verdict.title).font(.system(size: 13)).foregroundStyle(Theme.body)
                                if let note = tap.note { Text(note).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                            }
                            Spacer()
                            if tap.state == .done && tap.candidate.isReversible {
                                Button("Undo") { model.undo(tap) }.buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider().overlay(Theme.hairline)
            HStack(spacing: 12) {
                Button(model.isPaused ? "Resume" : "Pause 1 hour") { model.isPaused ? model.resume() : model.pause(hours: 1) }
                    .buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                Button("Look now") { Task { await model.look(force: true) } }
                    .buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                Spacer()
                Button("Permissions", action: openOnboarding).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.body)
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(12)
        }
        .frame(width: 380, height: 640)
        .background(Theme.surface)
        .environment(\.colorScheme, .light)
        .task { await model.refreshFeed() }
    }

    func section(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).kerning(0.6).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 4)
    }

    func symbol(_ tap: Tap) -> String {
        switch tap.state {
        case .failed: "!"
        case .undone: "↺"
        case .running: "…"
        default: "✓"
        }
    }
}
