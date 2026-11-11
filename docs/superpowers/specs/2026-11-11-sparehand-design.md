# Sparehand v1: design

Status: final draft for approval, 2026-11-11. Owner: Pulkit. Written with Claude from the brainstorming sessions.
Design canvas: https://claude.ai/artifact/F86WB16SPiDVKKn6QkQKru (private). POC results: `sparehand-pocs.md`. Watcher ideas: `sparehand-watchers.md`.

Items marked **[Claude's call]** were decided by Claude, not by Pulkit; check them while reading.

## 1. What it is and why

A spare pair of hands for your Mac. Sparehand quietly notices things on your computer that could be done for you, taps you with one specific suggestion, and does the work when you approve. Small jobs happen invisibly. Visual jobs (opening a browser, a terminal, typing a request to Claude Code) happen on **Sparehand's own invisible monitor**, which you can watch live in a small window or full screen in its own Space, "like watching a colleague work at the next desk".

Why: a person focused on one thing can't watch everything else on their Mac. Most of the "everything else" needs only basic judgement, which a small model on the Mac can make for free, privately, all day.

Goal for v1: Pulkit uses it every day and finds it genuinely useful; it produces a catchy demo video for X; early users react. No monetisation or long roadmap yet.

## 2. Goals, non-goals, anti-goals

Goals
- Useful daily on Pulkit's own Mac, for any Mac user (not developer-only).
- Taps feel worth it: specific, timely, never at a bad moment.
- Nothing happens without approval; everything that can be undone can be undone.
- The "watch it work" experience is delightful and is the demo's hero shot.
- Judging runs locally at no per-use cost.

Non-goals (v1)
- Night mode (queue at night, work overnight). Later.
- Reading email, messages or chat contents, or connecting cloud accounts (that is Claude Duet and Eney's territory).
- Learning by fine-tuning. v1 learns from simple counts and patterns.
- Windows/Linux, iPhone.
- Monetisation, accounts, sync.

Anti-goals (a failure even if it works)
- It nags. Too many taps, or taps during calls, screen shares or full-screen work.
- It touches the user's own windows or documents while working. (Happened in a POC; now a hard rule.)
- It sends, posts, follows, buys or deletes anything permanently without an explicit, specific confirmation.
- It records the user's screen or ships anything off the Mac.

## 3. Constraints

- macOS 26+, Apple silicon. Dev machine: MacBook Pro M5 Pro, 24 GB.
- No paid Apple Developer Program yet. Consequence: ad-hoc signed builds lose Full Disk Access / Accessibility / Screen Recording grants on every rebuild. **[Claude's call]** For daily dev use, sign builds with a self-made, stable code-signing certificate (Keychain Access) so grants persist; buy the $99 Developer ID before handing builds to other people.
- Open source (MIT), on GitHub under pulkitnagpal.
- Standalone product: no code shared with Quietkey.
- Must stay fast and quiet: under ~1% CPU and ~3 GB RAM while idle-watching on a 24 GB Mac (model loaded on demand or kept warm, see §6).

## 4. The experience (canvas screens 1-7)

1. **The tap**: a card slides in at the top right: what it noticed, the evidence (e.g. the 3 biggest Bin items), one primary action, "Not now", "Details". A small line says where it's decided and whether it can be undone.
2. **Watching it work (PiP)**: after approving a visual job, a picture-in-picture window shows Sparehand's own screen live, with a 3-4 step checklist and Pause / Stop / Watch full screen.
3. **Its own Space**: full screen, Sparehand's screen large, a "what I'm doing" rail, and Pause / Take over / Stop. Swipe back to your desk any time.
4. **Menu bar feed**: suggested taps waiting, today's done jobs with Undo, Pause 1 hour.
5. **Before you approve**: the plan step by step, where each step runs (on this Mac / on Sparehand's screen / Claude Code), what it will and won't touch, how to undo. "Approve and watch" or "Approve quietly".
6. **First run**: permissions explained one by one, each optional, each unlocking specific watchers.
7. **What it watches**: watcher families on/off, and "how often may it tap you".

Visual language **[Claude's call]**: warm neutral surfaces (#F7F6F3/#FFFFFF), ink #16161A, accent burnt orange #C2410C for "you decide" actions, teal #0F766E for "Sparehand is working", Space Grotesk headings + Inter body, a hand glyph as the mark.

## 5. v1 watchers

Each watcher = **signal** (what it notices, computed in code) + **judge** (local model: is there a helpful action the user would approve?) + **action** (what it does on approval).

| # | Watcher | Signal (code) | Action on approval | Where it runs | Undo |
|---|---|---|---|---|---|
| 1 | Bin | Bin over a size threshold; biggest + oldest items | Empty the listed items | invisible | none: explicit "can't be undone" confirm |
| 2 | Screenshot pile | Many screenshots on Desktop (281 on Pulkit's Mac) | Move to ~/Pictures/Screenshots/<month>, keep the last 2 days | invisible | move back |
| 3 | Downloads paperwork | New PDFs/images that look like invoices/receipts (PDFKit text, Vision OCR) | Rename by content (`aws-invoice-2026-03.pdf`) and file into Finance/<year> | invisible | rename + move back |
| 4 | Before a call | Calendar event with a video link in ≤5 min, notifications on | Turn on a Focus via Shortcuts, hide desktop icons | invisible | turn off |
| 5 | Routine | The same sequence repeated ≥3 days (app launches, shell commands, browser searches) | Open Terminal on Sparehand's screen, ask Claude Code to schedule it | **on Sparehand's screen, watchable** | delete the routine |
| 6 | Developer pack (off by default) | Idle Docker container using RAM; ports held by stale processes; Claude Code/Codex waiting for approval | Stop container / free port / bring the session forward | invisible | restart (container) |

**[Claude's call]** v1 ships 1-5 on by default and 6 off.

**Routine watcher (#5), in detail [Claude's call]**
- What it detects in v1: repeated *sequences* from three sources that need no extra permission prompt beyond Full Disk Access: app launch order (NSWorkspace), shell commands (zsh history), and browser history for Chrome/Arc/Dia (their history SQLite files; Safari's needs Full Disk Access).
- What it makes: a **Sparehand routine**, owned and run by Sparehand itself (stored in its SQLite, triggered by its own scheduler; a LaunchAgent wakes it if it isn't running). A routine is a small script (AppleScript and/or shell) plus a schedule or a one-tap "Run" button.
- Claude Code's role: it **writes and tests the routine's script** on Sparehand's screen (the watchable part), via `claude -p` with tools restricted to writing inside `~/Library/Application Support/Sparehand/routines/` and running that script once. The user's approval of the plan covers exactly that scope; nothing outside it is pre-approved. If Claude Code asks for anything else, the job pauses and the PiP shows "Needs you", with Take over / Stop.
- App-launch routines don't need Claude: Sparehand writes a "Start work" routine itself (open these apps/files in this order).
- Undo = delete the routine (and its script) from the feed.
- Demo staging: a `--seed` mode loads recorded example patterns so the hero video doesn't need 3 real days of history. Real detection still ships.

**Before a call (#4), in detail [Claude's call]**
- Focus: first run offers a one-click import of a bundled Shortcut ("Sparehand: Focus on/off"); Sparehand runs it with `shortcuts run`. If the user skips the import, the watcher only suggests turning on Do Not Disturb manually.
- "Notifications on" means: no Focus is active (the only state a public API reports).
- Hiding desktop icons is **dropped from v1**: it means changing a Finder setting and relaunching Finder, which touches the user's environment.

**Developer pack (#6), in detail [Claude's call]**: "bring the session forward" only activates that Terminal/app (the user asked for it by tapping). Approve/Deny from the notification is **not in v1**, because it would mean typing into the user's own terminal. "Tabs → comparison table in Notes" is the first v1.1 watcher (needs browser automation permissions and Claude to read pages).

The demo's hero sequence uses #5 (watchable) plus #1 and #4 (instant, relatable).

## 6. How it works

- **App**: native Swift/SwiftUI menu-bar app (`LSUIElement`), notifications via UNUserNotificationCenter with actions, plus our own tap cards for rich evidence.
- **Collectors** (cheap, event-driven where possible): NSWorkspace (frontmost app, launches), CGWindowList (window list), IOHIDSystem idle time, FSEvents on Desktop/Downloads/Bin, periodic disk/caches scans (caches took 5.8 s, so incremental and in the background), EventKit (calendar), zsh history, `docker`/`lsof` for the developer pack.
- **Judge**: local model, run only when a collector produces a candidate (never per frame). POC 1: Qwen 3.5 4B (MLX, 4-bit) decided 8/8 cases correctly in ~0.4 s using a "helpful action the user would approve" prompt with rules and examples. Numbers and grouping are done in code; the model judges and writes the card text.
  - Model residency **[Claude's call]**: load on demand when a candidate arrives, keep warm for 10 minutes, then unload. Typical idle memory stays well under 1 GB; the 2.8 GB peak is only while judging.
  - **[Claude's call]** Engine order: Apple's built-in Foundation Models when Apple Intelligence is on (no download); otherwise MLX Swift (`mlx-swift-lm`, which supports Qwen 3.5) with Qwen 3.5 4B 4-bit (~3 GB, downloaded on first run with clear consent).
  - Building MLX Swift needs the Metal compiler, which ships with Xcode (free) but not the Command Line Tools. **[Claude's call]** v1 runs the model in a small local helper, `mlx_lm.server` (Python MLX in an isolated environment, already working from POC 1), that the Swift app calls on localhost. It is replaced by MLX Swift in-process once Xcode is installed; Apple Foundation Models is used instead whenever Apple Intelligence is on.
- **Executor**: three kinds of action.
  1. Direct: FileManager moves/renames with a journal for undo; Bin emptying; process stop; Shortcuts for Focus.
  2. On Sparehand's screen: create a virtual display (private CGVirtualDisplay API, POC 2) with a fresh identity each time; open the job's app windows there; drive them via AppleScript/Accessibility; stream only those windows (ScreenCaptureKit window filter, POC 3) into the PiP / full-screen viewer.
  3. Hand-off to Claude Code: run `claude` in a Terminal window on Sparehand's screen with a prepared prompt, using the user's own subscription. If Claude Code isn't installed, the routine watcher offers the plan as text instead.
- **Rules the executor enforces**: only touch windows Sparehand created (by window id); never type into the user's windows; permanent deletion needs a specific confirmation; journal every change; stop instantly on Stop.
- **Taste and timing**: no taps during calls, screen sharing, full-screen apps, or while typing; at most N taps per hour by setting; "Not now" snoozes; "Never suggest this" disables that pattern.
- **Storage**: local SQLite for events, patterns, taps, decisions and the undo journal. Nothing leaves the Mac except Claude Code jobs the user approved.

## 7. Feasibility status (from POCs)

- Local judging: proven (POC 1).
- Invisible monitor + driving an app there: proven (POC 2).
- Live viewer showing only Sparehand's windows: proven (POC 3).
- No-prompt signals: proven; Bin needs Full Disk Access (POC 4).
- Not yet tested: browser tabs, Calendar, Focus toggling via Shortcuts, Apple Foundation Models (Apple Intelligence is off on this Mac), MLX Swift build.

## 8. Risks

- The virtual display uses a private API; a macOS update could break it. Fallback: drive apps in the background with Accessibility and show a recorded replay. **[Claude's call]** The fallback is not built in v1; it's a known risk.
- Permission fatigue: Full Disk Access, Accessibility, Screen Recording, Calendar. Mitigated by per-watcher, optional permissions.
- Platform overlap: Eney (MacPaw) covers Mac upkeep and proactive general tasks; Apple's Siri on macOS 27 adds on-screen awareness. Sparehand's angle is "does real work, on its own screen, watchable, local judging, open source".
- Same idea, different products: Jolie-Ni/DeskMate (watches a week, then suggests automations) and a Product Hunt "Tandem" proactive coworker. Neither shows the agent working on its own screen.

## 9. What's left to the builder

Exact thresholds (Bin size, screenshot count, routine repetition), card copy, model prompt examples per watcher, SQLite schema, how Pause/Stop interrupt AppleScript/Claude Code jobs, notification grouping.

## 10. Decisions so far
- Generic audience, not developer-only (Pulkit).
- Name: Sparehand (Pulkit).
- v1 = daytime taps; night mode later (Pulkit).
- Heavy reasoning goes to Claude Code on the user's subscription; the local model only judges (Pulkit, refined by Claude).
- Milestone 1 = the two demos in §5a (Pulkit).
- Standalone repo, MIT, no Quietkey code (Pulkit).
- v1 builds are for Pulkit's own Mac; the $99 Developer ID comes before sharing builds with anyone else **[Claude's call]**.
