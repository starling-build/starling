# Context menu: ours vs Windows File Explorer — 2026-08-23

Right-click a folder row, time the menu to pixels. Our file explorer running
as a view inside the Starling shell, against Windows File Explorer running
under the Windows shell — same PC, same folder (`C:\Users\starling`), same
row, same window rect, twenty warm right-clicks each.

Recorded separately because only one shell can own the desktop at a time,
which is stated on the film rather than left for the reader to wonder about.

- ours: `43192db`, the shell as `Shell=` (Starling registered, explorer absent)
- theirs: **Windows 11 Pro build 26200**, the stock shell — see the note below,
  Microsoft is changing this menu in the Insider channel
- DESKTOP-URK35LH, 4K panel at 200%, **30 Hz** — one composited frame is 33 ms
- rig: `test/bench/win-latency/` — `capture-ctxmenu.ps1` → `extract.sh` →
  `analyze-menu.py` → `compose-ctxmenu.py` / `filmstrip-ctxmenu.py`

## Result

| | first pixels | finished | frames |
|---|---|---|---|
| **Starling** | **66.6 ms** (0–133) | **66.6 ms** (0–133) | 2 |
| Windows File Explorer | 233.2 ms (200–267) | 299.8 ms (267–400) | 7 → 9 |

**4.5× faster to a finished menu, 3.5× to first pixels.** Per-rep tables in
`analysis-ours.txt` / `analysis-explorer.txt`, injector stamps in
`stamps-*.txt`. Both takes calibrated at 0.999 (video time against wall time),
so the timeline is not stretched.

Film and still, in the site's media directories:

- `ui/video/ctxmenu-latency.mp4` — 16 s, 1/8 speed, poster
  `ui/img/ctxmenu-latency-poster.jpg`
- `ui/img/ctxmenu-filmstrip.png` — every composited frame in a row

## What the difference actually is

Ours is **finished in the frame it first appears**: first pixels and settled
are the same frame in every rep. For a folder type it has seen before, the
type cache paints the panel complete on frame one and the shell's own verbs
reconcile behind it.

Explorer's menu is **absent for seven frames and then steps in complete** —
0, 0, 0, 0, 0, 0, 162, 216 on the appearance curve, a step and not a fade. It
holds until the shell's full verb tier has answered, which is the policy this
project measured its way out of in `11b60b7`. Its variance is ±1 ms across
twenty reps, which is what a hold looks like: not a race won consistently, but
a fixed wait.

Content is at parity, which matters more than the milliseconds: both menus
carry the same third-party rows (*Open in Terminal*, *Open in Terminal
Preview*) from the same registered handlers, because both ask through
`IContextMenu`. Ours draws them itself; the rows are Windows'.

## The instrument, and why it is not the obvious one

An earlier round of this used a GDI `CopyFromScreen` oracle and read **ours at
123–156 ms** and Explorer at ~300. The capture above reads ours at 67 ms and
Explorer unchanged.

**GDI lags the GL view**, so it penalised only our side — this project has now
paid for that lesson twice (the first time it produced a "~600 ms" that was
capture staleness). Desktop Duplication is the same instrument for both
contenders, which is the only property that makes a comparison worth
publishing.

Two more things the numbers depend on, both in the rig's README with the
traps: the pointer rests on the row for 700 ms before each click (right-click
sooner and you measure the hover work still in flight, which inflates both
sides and hides the difference), and the capture refuses to record unless a
pre-flight right-click actually opens a menu.

## What this is measured against, and when it expires

**Windows 11 Pro build 26200, stable, as shipped on this box.** The build is
recorded because a comparison against someone else's software is only true of
the version you ran.

On **2026-08-17** Microsoft announced context-menu work in the Insider
channel: *"the menu opens much more quickly"*, attributed to *"behind-the-
scenes engineering improvements"* and *"a cleaner default menu"*
([blog](https://blogs.windows.com/windows-insider/2026/08/17/improving-file-explorer-context-menu-faster-simpler-and-more-customizable/)).
No figures, no build number, no architecture — so there is nothing to compare
against yet, and nothing here is claimed about it.

Two things to get right when that build is measurable, both of which would
otherwise produce a flattering number in one direction or the other:

- **A cleaner default menu is a smaller menu.** Part of an announced speed-up
  that comes from removing rows is not the same axis as the one measured here.
  Count the rows in both menus and say so, or trim ours to match before
  timing; a 12-row menu against an 8-row menu is two different questions.
- **Their customisation settings change what the menu IS** (built-in commands
  toggled off, inline commands as text, extensions collapsed into a submenu).
  Pick one configuration, state it, and use it for both contenders.

Re-running is the rig's cheapest operation: both arms are one script each
(`capture-ctxmenu.ps1 -Label ours|explorer`), so the only real cost is putting
the box on an Insider channel — which is the shell-replacement test machine,
so that is a decision, not a step.
