# Windows latency: measuring it, and filming it

How long the shell takes to put pixels on screen after a keystroke, measured
against the native Windows shell — and how the side-by-side comparison films
are made. Built 2026-08-23 for the Start menu and the file explorer; the rig
is general and the traps are the reusable part.

Everything here runs against the physical Windows box (see the memory notes
for how to reach it). The scripts assume `ffmpeg` and `python3` on the box and
`ffmpeg`/`python3` + Pillow on the Linux side.

## The shape of it

1. **Capture** on Windows: a `ddagrab` recording of the real desktop, plus a
   sync marker that says exactly when the input went in.
2. **Extract** two per-frame signals from the video: marker brightness, and a
   coarse signature of the region the UI appears in.
3. **Analyse**: marker rising edge = t0; first frame whose region signature
   departs from the baseline = first pixels; first frame that reaches the
   final state = usable.
4. **Compose** the film from the same frames, aligned on t0.

## 1. Capture

`ddagrab` — ffmpeg's Desktop Duplication source. **Not GDI.**

```
ffmpeg -f lavfi -i "ddagrab=output_idx=0:framerate=30:draw_mouse=0" \
       -vf "hwdownload,format=bgra" -fps_mode passthrough \
       -c:v libx264 -preset ultrafast -crf 20 -pix_fmt yuv420p -t 34 out.mkv
```

- **GDI `CopyFromScreen` lags the GL view** — this project already paid for
  that lesson once (the "~600 ms" in `winshell-tasks.md` that turned out to be
  capture staleness). Timing our own shell with GDI penalises us and the
  comparison is worthless. One instrument for both contenders or don't bother.
- **ddagrab must run in session 1.** Session 0 has no desktop; it fails with
  nothing useful in the error.
- **`hwdownload` is required**: ddagrab hands out D3D11 frames and x264 cannot
  take them. Without it: *"Could not open encoder before EOF"*.
- **30 fps, not 60.** At 60 the pipeline sustains only ~0.96×, which compresses
  the video's timeline and shortens every measured latency by ~4%. At 30 it
  runs 0.998× even on a 1920×1800 crop, and full-screen 4K manages 0.974×.
  Frame size is not the bottleneck; frame rate is.
- The panel here runs at **29–30 Hz**, so one composited frame is 33 ms. That
  is the measurement quantum *and* what a person actually perceives.

### The sync marker

A topmost borderless window, flipped black→white with a **synchronous**
`Refresh()`, and the input injected immediately after — so the marker and the
keystroke land in the same composited frame and t0 is unambiguous. Any paint
delay in the marker is constant and cancels between the two contenders.

Two rules, both learned the hard way:

- **Give it `WS_EX_NOACTIVATE`.** While the marker holds the foreground,
  Windows will not activate the app being launched.
- **Keep the marker patch clear of the UI being measured.** Windows' Start
  menu draws *over* a topmost window (it takes the foreground), so a patch
  that overlaps it reads 248 (menu grey) instead of 255 and t0 becomes
  garbage. Measure the marker's real extent from a frame — WinForms scaled a
  160 px request to 258×160 here — and sample well inside it.

### Self-calibration

The injector stamps `QueryPerformanceCounter` at each rep. The rep-to-rep
spacing in the video is then checked against the rep-to-rep spacing in
reality, and the ratio corrects the result. It has come out 0.998–0.9997 every
time, which is how we know the timeline is not stretched. **Do this** — it is
three lines and it is the difference between a number and a guess.

## 2 & 3. Extract and analyse

```
./extract.sh out.mkv ours "125:120:50:920" "1000:1100:500:200" 16
python3 analyze-menu.py ours stamps.txt "OURS — Start menu"
```

- `analyze-menu.py` — first pixels and settled, for a surface that appears
  in place.
- `analyze-launch.py` — first pixels and *usable*, where usable is the first
  frame within 2% of the total change, with the final state sampled 3.3 s in.
  Relative, because the two contenders repaint different amounts of screen and
  a fixed pixel threshold is not neutral between them.

**Signature resolution is a measurement decision, not a detail.** At 16×16 a
whole-screen signature cannot see a file list populate, so it called Explorer
finished while its pane still read "Working on it…" — flattering the
competitor by 400 ms. Use 64×64 for anything with content in it. Look at the
actual response curve before choosing a threshold; the noise floor here is
0.05 and a real change is 20+.

**Twenty reps, not six.** The quantum is 33 ms, so with n=6 a single slow
launch moves the median a whole frame. A six-rep comparison once showed our
file explorer 50 ms "faster under Explorer than under our own shell"; at n=14
the gap vanished (the minima had been identical all along, which was the tell
that should have been believed). Treat any gap under ~2 frames as unmeasured
until it survives 20 reps, and quote the interquartile range beside the
median — if the two ranges overlap, there is no result.

**Report first pixels AND settled, separately.** Windows fades its Start menu
in, so "first pixels" flatters it and "settled" is the honest "the menu is
readable". Ours is identical on both, which is itself a finding.

## 4. Composing the film

`compose-menu.py` / `compose-launch.py` render every output frame with Pillow
and hand the sequence to ffmpeg. Not an ffmpeg filtergraph: the counter has to
freeze per pane, the captions change with state, and holds are inserted
mid-sequence — all trivial in Python and miserable in a filtergraph.

```
python3 compose-menu.py                 # writes frames/
ffmpeg -framerate 30 -i frames/%05d.png -c:v libx264 -preset slow -crf 20 \
       -pix_fmt yuv420p -movflags +faststart -y start-latency.mp4
```

**Cache the decoded frames.** The first version re-decoded a 4K PNG for every
output frame — 47 sources × 1600 outputs — and took minutes. One dict fixes it.

**Hard-link repeated frames** instead of writing the same PNG dozens of times;
holds and 1/8 speed mean most output frames are duplicates.

### What makes a few hundred milliseconds legible

The whole problem: 300 ms is real but invisible in a normal-speed recording.
Three devices, in order of how much they earn their place:

1. **Slow motion with a frozen stopwatch.** 1/8 speed for a menu, 1/6 for a
   launch. Each pane's counter runs, then freezes green at that pane's landing
   frame and stays frozen. The viewer reads the number off the screen.
2. **The photo-finish hold.** At the moment the faster one is done, hold the
   frame for ~2 s. Ours fully drawn; theirs bare wallpaper. That single
   held frame carries more than the rest of the film — it turns "faster" into
   "finished before the other one started".
3. **The filmstrip** (`filmstrip.py`). Every composited frame in a row, ms
   labelled, the landing frame outlined. At 29 Hz these *are* all the frames —
   nothing sampled, nothing interpolated — so the difference stops being a
   feeling and becomes something you count. This is the best answer to "how do
   you show a few hundred ms", and it doubles as a still image for a doc.

Both panes must be the **same screen region at the same scale**, aligned on
t0, with the method stated on the frame: same machine, same key, recorded
separately (only one shell can own the Win key at a time). Say that on the
title card rather than in a caption nobody reads.

Colours are carried from the film into any write-up so the two read as one
piece: `#0d1117` ground, `#58a6ff` ours, `#d29922` theirs, green reserved for
"finished".

## Driving the box

Every one of these has to run in session 1 through an interactive scheduled
task; SSH lands in session 0, which has no desktop:

```
schtasks /create /tn X /ru starling /it /sc once /st 00:00 /tr "wscript.exe C:\st\x.vbs" /f
schtasks /end /tn X     # ALWAYS end before run -- see below
schtasks /run /tn X
```

- **`schtasks /run` on a task still marked Running is refused silently.** End
  it first and verify afterwards; "SUCCESS: Attempted to run" means nothing.
- Wrap the `.cmd` in a `.vbs` (`sh.Run "...", 0, True`) or the console window
  it opens lands in your capture.
- **Never `Alt+F4` in a benchmark.** It goes to whatever has focus. With no app
  window up it closed our own dock, the supervisor lost its child, the desktop
  went black, and the capture recorded 58 s of nothing. Close by target:
  `FindWindowW` the class, `PostMessage(WM_CLOSE)`.
- **`$null` is not NULL in a PowerShell P/Invoke string parameter** — it binds
  as an empty string, so `FindWindowW("CabinetWClass", $null)` hunts for a
  window with an empty title and silently finds nothing. Use
  `[NullString]::Value`.
- **`$Args` is an automatic variable**; `param([string]$Args)` is silently
  ignored. Use any other name.
- **A function that `Write-Output`s narration and returns a bool** poisons
  `if (Check ...)` — the string is truthy, so every check "passes" (or fails).
  Use `Write-Host` for narration inside a function that returns a value.

## The context-menu arm

`capture-ctxmenu.ps1` is the pointer-driven sibling of `capture-menu.ps1`:
right-click a folder row, time the menu. Same marker, same stamps, same
analyzer (`analyze-menu.py`, which now infers the signature resolution from
the file rather than assuming 16x16). `compose-ctxmenu.py` and
`filmstrip-ctxmenu.py` make the film and the still.

Measured 2026-08-23, 20 warm reps each, medians — ours under Starling,
Explorer under the native shell:

| | first pixels | finished |
|---|---|---|
| Starling | **66.6 ms** | **66.6 ms** (the same frame) |
| Windows File Explorer | 233.2 ms | 299.8 ms |

Ours is finished in the frame it first appears, because the type cache paints
the panel complete. Explorer's menu is *absent* for seven frames and then
steps in — it holds until its shell tier is complete, which is the policy we
removed. **Note how much better this instrument is to us than GDI was**: a
`CopyFromScreen` oracle read our menu at 123–156 ms and Explorer at ~300, so
it penalised only the GL side. One instrument for both contenders, always.

Four traps beyond the ones above, each of which produced a plausible-looking
wrong answer:

- **The sync marker must not take activation.** A WinForms marker without
  `WS_EX_NOACTIVATE` steals the foreground; Explorer answers a right-click
  while unfocused and OUR file explorer does not, so the capture recorded
  twenty reps of nothing while the marker signal looked perfect. The analyzer
  says "0 reps detected" over 20 clean marker edges — that phrasing means the
  REGION never changed, not that t0 was missing.
- **A "minimize everything else" step must skip the target's whole PROCESS,
  not just its window.** Hosted in the shell, the file explorer's siblings are
  the dock and the desktop, and the dock's window is titled ("Starling Dock"),
  so a title-based skip minimizes the shell's own chrome. A minimized host has
  no popups, and the pre-flight then reports a shell that cannot open menus.
- **Do not dismiss the menu by clicking "somewhere empty".** A context menu
  opens at the pointer and extends down and right; the window's bottom strip
  is *inside* it, so the dismissal invokes whatever row is there — a run ends
  up with a stack of Properties dialogs and every rep starts from a different
  state. Press Escape, and check in pre-flight that Escape actually closes it
  rather than assuming.
- **Assert the menu opens before recording.** `capture-ctxmenu.ps1` opens one
  menu, samples a patch, and refuses to record if nothing changed. Three of
  the failures above were only cheap to find because of it.

## Comparing against the native shell

Only one shell can own the Win key, so the two configurations are recorded
separately and that is stated on the film. To switch:

- ours → native: `--unregister-shell`, kill `WinShellBar`, `--restore-taskbar`,
  start `explorer`.
- native → ours: `--register-shell` and **reboot** (autologon brings it back).

**Do not use `C:\dist\register.ps1` for this** — it blanks `DefaultPassword`,
which parks the box at LogonUI with no interactive session and no way to run
scheduled tasks remotely. Check the password length is 13 first.

Warm both sides before recording. Windows keeps `StartMenuExperienceHost`
resident and our launcher is parked by design, so steady state is what both
are built for; measuring either cold measures process creation instead.

`zorder-stress.ps1` is not part of the film pipeline — it is the regression
test for the P0 that this measurement work uncovered (apps landing invisibly
behind the desktop). Launch → close → launch, repeatedly, asserting the
desktop is never above the app. A single launch passes even when the bug is
present.
