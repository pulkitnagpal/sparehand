# Sparehand POC results

## POC 1: local models on the MacBook Pro M5 Pro, 24 GB (2026-11-11)
Runtime: mlx-lm 0.32.2 (MLX 0.32.4), 4-bit models from mlx-community, greedy decoding, thinking off.
Bench: 19 watcher-style tasks (8 "show a card?" judgements, 4 extractions, 2 tab groupings, 5 notification texts).
Scripts: scratchpad `llmbench/bench.py` and `judge2.py` (copy into the product repo when it exists).

| Model | Disk | Peak RAM | Median per decision | Gen speed |
|---|---|---|---|---|
| Qwen3.5-4B-MLX-4bit | 3.1 GB | 2.8 GB | 0.34 s | 48 tok/s |
| Qwen3.5-9B-MLX-4bit | 6.0 GB | 5.5 GB | 0.50 s | 40 tok/s |

Findings
- Notification writing: both good (5/5 usable). 9B slightly more specific.
- "Should we interrupt?" framing made both models shy (4B 6/8, 9B 4/8: said no to almost everything).
- Reframed as "is there a helpful action the user would approve?" with rules + 3 examples: **both 8/8**, 4B in ~0.4 s each.
- Arithmetic (summing minutes) wrong on both: do maths in code, give the model the totals.
- Topic grouping of tabs: 4B 0/2, 9B 1/2. Use embeddings + clustering in code, model only names the groups.
- Counting steps in a shell routine: both said 3 for `cd && git pull && docker compose up -d && npm run dev` (my answer key said 4; arguably ambiguous).

Design rules that follow
1. Signals and numbers come from code; the model judges and words.
2. Judge prompt = value framing + rules + few-shot examples (per watcher family).
3. 4B is enough for always-on judging; 9B optional for richer text. Heavy work goes to Claude Code.
4. Apple's built-in model not tested yet: Apple Intelligence is off on this Mac.

## POC 2: the agent's own invisible monitor (2026-11-11)
Code: `sparehand-virtual-display-poc.m` (Objective-C, ~120 lines). Result GIF: `sparehand-virtual-display-poc.gif`.
- Created a 1920x1080 virtual display ("Sparehand Workspace") with the private `CGVirtualDisplay` API on macOS 26.5. It appeared at x=1512 (right of the built-in screen) and vanished when the process exited.
- Opened a new TextEdit document, moved its window onto the virtual display, and filled it in step by step via AppleScript (no mouse/keyboard takeover).
- Recorded the virtual display with ScreenCaptureKit while the real screen stayed untouched: 6 frames.
- **Bug found and fixed:** the first run moved the *front* TextEdit window, which was the user's own document (left unmodified; macOS moved it back when the display vanished). Rule: the agent only ever touches windows it created, addressed by name/ID.
- The virtual display shows the wallpaper and desktop icons; the product should cover it with its own clean backdrop window so the live view looks intentional (and leaks nothing on stream).
- Private API: could break in a future macOS; fallback is approach 2 (background Accessibility actions) with a recorded replay.

## POC 3: watch it work, live (2026-11-11)
Code: `sparehand-live-viewer-poc.m`. Recording: `sparehand-live-viewer-poc.gif` (21 snapshots taken from the live stream).
- A normal Mac window ("Sparehand — live", full-screen capable so it gets its own Space) streams the invisible monitor at up to 30 fps with ScreenCaptureKit while the agent types into its own TextEdit document there.
- The stream includes **only the agent's own window** (SCContentFilter including that one window) on a dark backdrop: no wallpaper, desktop icons or other windows.
- Two rules learned the hard way:
  1. macOS remembers which monitor a window was on. Give the virtual display a fresh serial number every time, or windows that were ever moved there (by mistake) reappear on it.
  2. Filter the stream by window, never by app: an app-level filter showed the user's own TextEdit document behind the agent's.
- The user's documents stayed unmodified and their windows never moved in the final run.

## POC 4: signals readable with no permission prompt (2026-11-11)
Code: `sparehand-signals-poc.swift`. Printed counts only, never contents.

| Signal | Result on this Mac | Cost | Permission |
|---|---|---|---|
| Frontmost app | works | 1 ms | none |
| Running apps | 17 regular apps | 5 ms | none |
| Window list + titles | 2 windows, 1 with title | 37 ms | titles need Screen Recording (granted to the parent here) |
| Idle time (no keyboard/mouse) | works (IOHIDSystem) | <1 ms | none |
| Disk free | 423 of 994 GB | 19 ms | none |
| Bin size | **blocked** | - | Full Disk Access |
| Downloads | 10.7 GB, 38,624 items | 0.6 s | none here (may prompt in a sandboxed/new app) |
| Screenshots on Desktop | **281** | 23 ms | none |
| ~/Library/Caches | 55.8 GB, 243k items | **5.8 s** | none; scan incrementally in the background |
| zsh history | 4,914 lines | 64 ms | none |
| Battery | 96%, discharging | 68 ms | none |
| Docker CLI | installed | - | none |

Still to test with you present (they show permission prompts): browser tabs (Automation per browser), Calendar (EventKit), Focus/Do Not Disturb state, Accessibility window details.
Real watcher material from this Mac: 281 screenshots on the Desktop, 55.8 GB of caches, 10.7 GB in Downloads.

## Design canvas
Sparehand v1 design (private): https://claude.ai/artifact/F86WB16SPiDVKKn6QkQKru
Seven screens: the tap, picture-in-picture live view, full-screen Space, menu bar feed, before-you-approve details, first-run permissions, watcher settings.
