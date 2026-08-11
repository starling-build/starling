# Agent workspace demo — talk track (~3 min)

Revised 2026-08-11 to match the redesigned landing page: the agent workspace
*is* the story now, not the twist. Supersedes the pre-redesign draft where the
agent reveal waited until beat 6. The general-desktop tour is covered by the
existing hero video (`ui/video/starling-demo.mp4`); this video is the agents
section's proof.

**Framing to hold the whole way through:** *your AI agent gets a desktop of
its own — you keep yours, you can watch, and you can step in.*

Mechanical notes before recording: the mode toggle is **Ctrl+Down**
(`DesktopShell.swift:2598`). Every "point at X" moment is a recording-zoom
moment — the crop follows the pointer. Name no specific agent on the
soundtrack; "a coding agent" throughout.

---

### Beat 1 — Your desktop, your work (~15s)

**Screen:** ordinary desktop with your own windows open — Files, a browser
with something half-read.

> "This is my desktop, mid-workday. I'm about to hand a project to an AI
> agent — and the point of everything you're about to see is that this
> desktop stays mine."

### Beat 2 — The agent's room (~20s)

**Screen:** press **Ctrl+Down**; the workspace slides in. Rename it `web`.
Point at the three columns as you name them.

> "One keystroke: a workspace. Think of it as the agent's room, not a window
> on my desk. Rooms on the left. The driver — the one thing the room is built
> around — down the middle. And on the right, tabs: everything the driver
> opens lands beside it, never on top of it."

### Beat 3 — Hire the driver (~20s)

**Screen:** click **+**, pick Terminal, start a coding agent in it.

> "A room needs a driver. Mine is a terminal — because the real driver is
> what runs inside it: a coding agent. Any of them."

### Beat 4 — The task (~20s)

**Screen:** type visibly, then Enter:

> *(typing)* `Build a small web app — a one-page site that shows the current
> time in five cities. Serve it locally and open it in Chrome when it's done.`

> "A real task, end to end: write it, serve it, show me."

### Beat 5 — Separation, proven (~25s)

**Screen:** while the agent works, **Ctrl+Down** back to your desktop. Move a
window. Scroll the browser. Keep working.

> "Meanwhile — my desktop. Nothing popped over my work, nothing stole focus,
> and that's not the agent being polite. It can only operate on apps it
> opened itself. My windows aren't in its world at all."

*This beat is the landing page's central claim on camera. Don't rush it.*

### Beat 6 — Watch it work (~20s)

**Screen:** Ctrl+Down back to the workspace. Chrome has landed as a tab
beside the driver; the clock page is live and the time is right.

> "Back in its room: it finished, opened Chrome — and the workspace caught
> it, as a tab beside the agent. That's the real Chrome, serving the real
> site."

### Beat 7 — Step in (~25s)

**Screen:** click into the Chrome tab, scroll it. Have the agent open the
project in VS Code; click into that tab, point at the code, then type a
follow-up instruction to the agent (e.g. "make the city names bold").

> "And these are real apps, mine to click. I can inspect what it built,
> correct it, redirect it — then hand it back and let it carry on. Watch it
> work, step in anytime."

### Beat 8 — The why, one sentence (~10s)

**Screen:** hold on the full workspace.

> "This works because the whole desktop is one program. A window is a widget
> it can place anywhere — including in an agent's room."

### Close (~18s)

**Screen:** Ctrl+Down back to the desktop; hold on the untouched windows.

> "And when I flip back — my desktop, exactly as I left it. Nothing moved,
> nothing stole focus; the agent's whole world stayed in its room. One more
> thing: this recording was made by the desktop's own recorder, and every
> close-up was its zoom following my pointer."

*Why not "delete the room"?* Rehearsal (2026-08-11) showed removal does NOT
stop a workspace's apps — the menu reads "Remove (keeps N open)", and it is
disabled entirely for the last workspace. The honest close is the untouched
desktop, which is also the page's central claim.

---

## Why it changed from the previous draft

- **Agent-first, not twist.** The old script spent ~2 minutes on the desktop
  and workspace anatomy before revealing the agent. The landing page now
  sells "Built for AI agents" in the first screen, so the video opens on the
  hand-off premise in 15 seconds.
- **Separation is a beat, not dead-air insurance.** "Flick away while it
  generates" was filler in the old script; it is now the proof of the page's
  strongest claim (dedicated workspace, agent can't touch or see yours).
- **Intervention is a beat.** The page headline is "watch it work, step in
  anytime" — so the video shows a click into the agent's Chrome and VS Code
  and a live correction.
- **No agent named** (page is vendor-neutral now), **no Mac comparison**
  (dropped from the hero), and the architecture line is demoted from
  punchline to one closing sentence.
- **Same task** (five-city clock page): verifiable on camera at a glance —
  the time being right proves it's live — no accounts, no API keys, fast to
  generate.
