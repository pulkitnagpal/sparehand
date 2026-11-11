# Sparehand v1: local first, cloud second

Supersedes the noticing part of `2026-11-11-sparehand-design.md` (the hand-written watchers). The tools, journal, Notes and
browser drivers, agent screen, live viewer and the menu-bar UI from milestone 1 stay.

## Intent

Sparehand is a proactive personal agent for any Mac user, marketed as **local first, cloud second**. It watches how you work,
notices what's worth doing, and does it when you approve, often on its own invisible screen that you can watch. It learns you over
time.

No one writes a rule per use case. The goal is the fullest use of the Mac's own model without lowering the quality of what the
user sees. The cloud is used only where a local model would give a worse answer, and that share should shrink week by week.

## Evidence so far

- **Local Qwen 4B as the decider** (what to offer): 12/22 on the synthetic test. Qwen 9B scored 10/22.
- **Claude Sonnet 5.5 as the decider:** 21/22.
- **Local Qwen 4B as a screener** ("is anything here worth a closer look?"):
  - It let through 10 of the 10 situations worth acting on.
  - It ruled out 6 of the 12 quiet snapshots.
  - About 0.3 s each.
  - Ordinary snapshots dominate a real day, and those are the easiest to rule out.
- **Real Mac, first snapshot:** Sonnet found a 733 MB leftover Dia installer, which the user called good.
- **Pending:** the shadow day (Opus grades with hindsight) gives the real-day numbers. They tune the thresholds, not the
  architecture.

Conclusion: a small local model is reliable at saying "nothing here" and at repeating what it has been shown. It isn't yet reliable
at spotting new things. The architecture gives each job to whoever does it best.

## The decision ladder (each step can end it, cheapest first)

1. **Sense (code, on the Mac).** Generic signals only:
   - front app, window titles, fullscreen and idle state
   - app launches today and minutes per app
   - Desktop and Downloads: counts, kinds, newest items and new items, with Vision OCR of new images
   - Dia, Chrome and Safari tabs (a browser that isn't running is never launched)
   - terminal history
   - RAM and CPU per app, Docker containers, memory pressure, disk, battery
   - Bin size (only with Full Disk Access)
   - Everything passes the redactor (keys, tokens, passwords, URL query strings).
2. **Policy (code, on the Mac).** Stop here when:
   - the user is in fullscreen, sharing their screen, in a meeting app, or idle
   - nothing salient changed since the last look
   - the card limit has been reached (at most 3 an hour, 12 a day)
3. **Screen (Qwen 4B, on the Mac).** "Is anything here worth a closer look?" Tuned for recall: when unsure, say yes. Most
   snapshots end here, and nothing leaves the Mac.
4. **Learned skills (Qwen 4B, on the Mac).**
   - Every offer the user accepted becomes a skill: the situation, the tool, an args recipe and the card wording.
   - When a snapshot matches a known skill (for example, screenshots piling up again), Qwen fills in the args. Extraction is what
     small models do well.
   - The card is made from the skill without the cloud.
   - Code still checks every named file or app against the snapshot.
5. **Claude (cloud, only for new situations).** The redacted snapshot goes to Sonnet 5.5 with:
   - what counts as help
   - the tool catalogue
   - the user's memory
   - today's offers

   It answers with the tool, args, card text, a "why I noticed" line and a confidence score.
6. **Validate (code).**
   - The tool and its args schema are valid.
   - Every target named exists in the snapshot.
   - The copy doesn't contradict the plan.
   - Confidence is at least 4.
7. **Card.** The existing tap card, plus a "Why I noticed" line and a small badge: "noticed on your Mac" or "asked Claude".
   Buttons: the action, Not now, and Never for this.
8. **Act (code, on the Mac, journaled).**
   - Tools: `organize_files`, `move_to_bin`, `quit_app`, `stop_container`, `create_note`, `research_to_note` and `show_report`.
   - Every reversible action can be undone from the card and the feed.
   - Nothing runs without a tap in v1.
   - `research_to_note` is the one heavy cloud job:
     - Claude reads the pages using the Messages API `web_fetch`, or WebFetch on the CLI backend, and returns a table.
     - Sparehand writes the table row by row into a Notes window on the agent screen, which the user watches in the live viewer.
     - A progress strip shows Claude's steps.
     - There's no terminal anywhere.

## Learning, and moving more local over time

- Every decision and every piece of feedback is logged on the Mac: the snapshot, the screen result, the skill match, Claude's
  answer, and the user's tap, "Not now" or "Never".
- **Memory:** after every 5 pieces of feedback, a memory of at most 15 lines is rewritten. For example: "keeps screenshots on the
  Desktop on purpose".
  - It's fed into the screener, the skill matcher and Claude.
  - The user can see and edit it.
  - In v1 Claude does the rewrite. Moving it local is a later step.
- **Skills** grow from accepted Claude offers, so each new kind of help is asked of Claude once and then runs on the Mac.
- **Later (v1.x):**
  - A nightly LoRA fine-tune of Qwen on the logged Claude decisions, with `mlx_lm` on the Mac.
  - When Qwen agrees with Claude on held-out cases at least 95% of the time, it takes over that kind of decision, and Claude
    checks a small sample.
- **What the user sees:** the feed shows "This week: N% of decisions made on your Mac".

## Local-only mode

There's a switch in settings. With no cloud at all:
- the screener and learned skills still work
- new situations aren't offered
- research jobs are off

It's honest about doing less, and nothing ever leaves the Mac.

## Models and connection

- **One model interface, three backends:**
  - **Local:** an OpenAI-compatible `mlx_lm.server` run by a bundled helper.
    - It loads on demand and unloads after 10 idle minutes, about 3 GB while loaded.
    - It's downloaded at onboarding with consent.
  - **Claude API:** for users.
    - The user pastes an Anthropic API key, which goes into Keychain.
    - Raw HTTPS calls, since Swift has no official SDK.
    - `web_fetch` handles research, so no Claude Code, Node or Python is needed.
  - **Claude CLI:** for dev and the demo. `claude -p`, using the OAuth token from Keychain item `sparehand.claude-oauth` and the
    isolated config directory `~/.sparehand-claude`.
- Keys are never logged or shown.
- Onboarding says in plain words what stays on the Mac and what goes to Claude, and that it's redacted.
- "Pause Sparehand" lives in the menu bar.
- **No Agent SDK or Claude Code harness in v1.** Every decision is a single call, and research is covered by `web_fetch`. The SDK
  stays an option for open-ended jobs later, such as coding or the night shift.

## Demos

- **Demo 1, background clean-up.**
  - The Demo account has a messy Desktop (about 25 screenshots) and Downloads holding old installers.
  - **First run:** the screener passes the snapshot, Claude notices it, and the badge says "asked Claude". Approve, the files
    move, and Undo works.
  - **Then:** new screenshots land, the learned skill matches on the Mac, and the badge says "noticed on your Mac". This shows
    local first in action.
  - The Bin card is dropped, because it needs Full Disk Access.
- **Demo 2, watch it work.**
  - Tabs about one purchase, such as standing desks.
  - Claude offers a comparison note. Approve, and the live viewer shows the agent screen while the table fills into Notes.

## Non-goals for v1

- the night shift
- the nightly fine-tune
- clicking inside other apps (computer use)
- calendar, mail and notifications
- anything beyond these three browsers
- acting without a tap

## Done means

- Both demos run end to end in the Demo account.
- On the real Mac:
  - about 1 card per active hour or fewer
  - Opus-graded precision of at least 70%
  - the screener lets through at least 95% of Claude's good offers
  - the majority of snapshots are decided entirely on the Mac
- All tests pass.
