# The Windows shell gate

One command, run from here, that says whether the Windows shell on the
physical box is in a shippable state:

```bash
test/win/run-gate.sh                          # the usual box
STARLING_WIN_HOST=user@host test/win/run-gate.sh
```

It exits 0 when every check passes, prints what failed when they don't, and
brings back a screenshot of the failing screen.

## What it checks, and why each one is here

| check | looks at | the bug it would have caught |
|---|---|---|
| the five session processes | handles | a supervisor that refused to start, or two shells fighting over one screen |
| explorer alive, owning no chrome | handles | packaged apps that will not launch; explorer's taskbar or desktop showing over ours |
| the dock reserves its strip | the work area | maximized windows running underneath the dock, with the dock still drawn |
| the desktop surface is on screen | handles | nothing drawing a wallpaper |
| there is a wallpaper, not a black screen | **pixels** | a black screen with a dock on it — every handle correct, nothing drawn |
| the dock is drawn along the bottom | **pixels** | a reservation that holds while the dock itself never paints |
| the shell holds the minimize target | handles | minimized apps left as title-bar stubs sitting on the dock |
| a minimized window leaves the screen | handles | the same, from the app's side |
| the file explorer opens, minimizes, comes back | handles + **pixels** | Files minimized into nowhere; and a restored window that comes back blank |
| a packaged app launches, minimizes, comes back | handles + **pixels** | Calculator dying two seconds after launch; and an empty frame that passes for a running app |
| the dock knows which app a packaged window is | the shell's own answer | every Store app getting a SECOND dock tile instead of lighting its pinned one — with Settings and Calculator sharing that tile, because both frames belong to ApplicationFrameHost |

Every row is a bug that actually shipped, which is the bar for being in here.

## Why some checks look at pixels

The two worst bugs this shell has had were invisible to every window API. A
black screen with a dock on it: every handle present, correct and in the right
place, and nothing drawing a wallpaper. And a window that "came back" from
minimized as a white rectangle, because a surface view nobody asked for a
frame paints nothing. Both pass a handle check and fail a person looking at
the screen, so those checks look at the screen.

The measurements are deliberately coarse — "does this region have variety",
"is this strip dark" — because a gate that asserts exact pixels fails on a new
wallpaper and teaches everyone to ignore it.

**What is deliberately NOT a pixel check** is "did minimizing leave something
on the desktop". The obvious form — diff the band above the dock before and
after — cannot tell a stub appearing from another app repainting behind it,
and on this box it cried wolf on exactly that. It asks Windows instead: is any
window minimized, visible, uncloaked, and still on screen. Two kinds of
minimized window sit at plausible coordinates and never paint — DWM's
notification window, and suspended packaged apps, which are cloaked — so both
are excluded, or the check fails on a clean desktop.

## Why it runs the way it does

SSH lands in **session 0**, which has no desktop. Anything asking about
windows there is answered about a desktop nobody is looking at — window
enumeration comes back empty or phantom, and screenshots are black. So
`run-gate.sh` copies `gate.ps1` to the box and runs it as an **interactive
scheduled task** in the logged-in session, then waits on a sentinel file.

Screenshots are downscaled **on the Windows side** before they cross the
wire. A full 4K PNG is ~16 MB, and a couple of those are enough to fill a
scratch directory and take the tooling down with it.

## What it does not cover

- **Z-order**: `test/bench/win-latency/zorder-stress.ps1` is the separate,
  slower one — 24 launch/close cycles with three shell restarts. Run it when
  touching the desktop plane or window layering.
- **Looks**: nothing here says the dock is drawn correctly, only that it is
  there and reserving space. The failure screenshot is for human eyes.
- **The Linux desktop**: that is `test/run.sh` and `test/vm.sh`.

## Leaving the machine as it was found

The probe window is destroyed, the file explorer is put back to the visibility
it had, and Calculator is **closed, not killed**: its window belongs to
ApplicationFrameHost rather than to the app, so killing the process leaves an
empty white frame sitting over the desktop — untidy, and enough to fool the
next check that looks at the screen. A failing run may leave an app open, on
purpose, so the state can be looked at.

A screenshot is written on every run, pass or fail, and `run-gate.sh` copies
it back. On a pass it is the evidence; on a failure it is the diagnosis. It is
downscaled on the Windows side first.
