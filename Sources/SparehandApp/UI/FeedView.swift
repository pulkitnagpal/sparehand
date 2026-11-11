import SparehandCore
import SwiftUI

/// The menu-bar feed: waiting cards, then today's done work with Undo. One line per thing.
struct FeedView: View {
    @ObservedObject var model: AppModel
    var openOnboarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HandMark(size: 13, color: .white).frame(width: 24, height: 24).background(Theme.decide, in: RoundedRectangle(cornerRadius: 7))
                Text("Sparehand").font(Theme.heading(16)).foregroundStyle(Theme.ink)
                Spacer()
                Circle().fill(model.isPaused ? Theme.pending : Theme.working).frame(width: 7, height: 7)
                Text(model.isPaused ? "Paused" : "Watching").font(.system(size: 12)).foregroundStyle(Theme.body)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
            Group {
                if model.claude == nil {
                    Text("Connect Claude in Settings to get new suggestions.")
                } else if !model.localReady {
                    Text("Getting ready…")
                }
            }
            .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 16)
            Spacer().frame(height: 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if !model.pending.isEmpty {
                        section("FOR YOU")
                        ForEach(model.pending) { tap in
                            HStack(spacing: 10) {
                                Text(tap.verdict.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                Spacer()
                                Button(tap.verdict.actionLabel) { model.approve(tap) }.buttonStyle(PillButton(fill: Theme.decide, text: .white))
                                    .disabled(model.busyTapID != nil)
                            }
                            .padding(10)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    section("TODAY").padding(.top, model.pending.isEmpty ? 0 : 8)
                    if model.done.isEmpty {
                        Text("Nothing yet.").font(.system(size: 12.5)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    }
                    ForEach(model.done) { tap in
                        HStack(spacing: 10) {
                            Image(systemName: symbol(tap)).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tap.state == .failed ? Theme.decide : Theme.working).frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tap.verdict.title).font(.system(size: 13)).foregroundStyle(Theme.ink).lineLimit(1)
                                if let note = tap.note { Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1) }
                            }
                            Spacer()
                            if tap.state == .done && tap.candidate.isReversible {
                                Button("Undo") { model.undo(tap) }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.decide)
                            }
                        }
                        .padding(.horizontal, 4).padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider().overlay(Theme.hairline)
            HStack(spacing: 14) {
                Button("Look now") { Task { await model.look(force: true) } }
                    .buttonStyle(PillButton(fill: .white, text: Theme.ink, border: Theme.hairline))
                Button(model.isPaused ? "Resume" : "Pause") { model.isPaused ? model.resume() : model.pause(hours: 1) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.body)
                Spacer()
                Button("Settings", action: openOnboarding).buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.body)
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(12)
        }
        .frame(width: 340, height: 440)
        .background(Theme.surface)
        .environment(\.colorScheme, .light)
        .task { await model.refreshFeed() }
    }

    func health(_ name: String, _ ok: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(ok ? Theme.working : Theme.pending).frame(width: 6, height: 6)
            Text(name).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
        }
    }

    func section(_ title: String) -> some View {
        Text(title).font(.system(size: 10.5, weight: .semibold)).kerning(0.6).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 2)
    }

    func symbol(_ tap: Tap) -> String {
        switch tap.state {
        case .failed: "exclamationmark"
        case .undone: "arrow.uturn.backward"
        case .running: "ellipsis"
        default: "checkmark"
        }
    }
}
