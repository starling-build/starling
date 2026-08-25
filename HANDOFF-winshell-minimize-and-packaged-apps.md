# Checkpoint — Windows shell, 2026-08-25 (updated later the same day)

Where the Windows shell stands after the minimize / packaged-app work, what is
verified, and every issue found along the way that is not fixed. Written so
the next session can start from evidence rather than from scratch.

Box: the physical machine (`starling@192.168.68.60`), running mainline as the
registered `Winlogon\Shell` with autologon. Mainline is pushed through
`fa2f00f`.

**The blocker below is fixed.** Issues 1 and 3 are done; the explorer service
is on by default again and the gate is 10/10 with nothing skipped. What is
left is issues 2, 4, 5 and 6.

## What landed and is verified

| | commit | verified by |
|---|---|---|
| Minimized apps stop leaving title-bar stubs on the desktop | `f9bcb0a` | probe minimize parks at −32000; matches native measured the same night |
| The file explorer comes back from minimized | `54379bb` | Win+E → minimize → Win+E, window returns painted |
| Packaged (Store) apps can run, **on by default** | `a358345`, `1d2528b`, `d2c8c75` | Calculator activates, shows, minimizes, restores |
| A repeatable Windows gate, 10 checks, 4 of them pixel | `222eca7`, `8b8aae8`, `fa2f00f` | 10/10 in the shipping configuration, nothing skipped |
| Idle CPU regression found and fixed; perf re-measured | `406dcd4` | 60 s idle sample; 20-rep latency capture |
| The dock reserves its strip with explorer running | `d2c8c75` | both configurations; maximized window stops at the dock |

Numbers, for comparison next time: idle **0.31%** of one core / 142 MB for the
shell (of which banners' notification poll is 0.26%), explorer **0.05%** /
227 MB when the service is on, dwm 0.00%. Win+E → file explorer drawn,
**median 146 ms** over 20 reps, arriving fully painted in one frame.

## Open issues

### 1. The work area, with the explorer service on — FIXED

**What it was.** With the explorer service running, the dock drew its strip and
reserved nothing, so maximized windows ran underneath it. Reproducible by
restarting the shell while explorer was alive — which is what a crash respawn
and every deploy do.

**Why four correct-looking fixes all failed.** Re-asserting at startup, on
explorer's `TaskbarCreated`, from a self-healing watcher, and all three
together each ended in the same call: set the work area with the flag that
broadcasts "the work area changed". That broadcast is explorer's cue to
recompute it, and what explorer computes is *nothing is reserved* — its own
taskbar is autohidden and its appbar list has never heard of the dock. The
notification meant to publish the reservation was what destroyed it. Measured
with our shell not even running: set it silently and it holds for fifteen
seconds; set it with the broadcast and it is gone by the next read; kill
explorer first and the broadcast is harmless.

So the work area is now set silently and announced by hand to every top-level
window except explorer's.

**The second half**, which is why "just serve it ourselves" had to come with
it: the appbar service was forwarding the dock's own registration to explorer,
where it could never land. Windows hands a same-process caller a direct heap
pointer instead of shared memory, and explorer cannot read our heap — it
returned success anyway. A third-party appbar, which travels through real
shared memory, forwarded perfectly, so the failure looked like it was about
our dock specifically. It was.

**One trap worth not repeating.** The obvious test for "is explorer the shell"
is whether it has a desktop window. It does — the service explorer creates one
and we hide it rather than prevent it, and the lookup finds hidden windows. A
probe said otherwise only because it asked through PowerShell, where a null
string argument becomes an empty string, so it searched for a window *titled*
empty and found none. That is the third time this tree has paid for that
conversion. The shell now decides it is the shell because it is the process
that hid explorer's taskbar, which is a statement of intent rather than a
guess.

Commit `d2c8c75`. Verified in both configurations: reserved after a restart
with explorer alive, a stomp repaired within a second, a third-party appbar
still working alongside the dock, and a maximized window stopping at the dock.

### 2. Win+E latency: 146 ms against 110 ms recorded — unmeasured, not unchanged

One 33 ms frame apart, and the rig's own rule is that anything under two
frames is unmeasured until it survives a proper A/B. The A/B that would settle
it is the same capture with the explorer service off; it was set up and not
completed. Do that before believing either number.

### 3. An unrecognised command-line flag starts a whole second shell — FIXED

Anything mistyped fell through every mode test into the last one, which tests
nothing, and came up as a second dock that fought the real one for the
minimize target. It now refuses the argument and exits. Commit `618e098`.

### 4. Deploying races Winlogon's respawn and leaves two supervisors

`AutoRestartShell` is on, so killing the shell to swap the binary gets a new
one started within a second — and if the deploy script also starts one, the
session runs two supervisors and two chromes. Every measurement taken in that
state is wrong. The deploy scripts on the box now rename the running exe
rather than overwriting it, and prune duplicates by role afterwards, but
nothing in the tree enforces it.

### 5. Windows left over from before the fix cannot be cleaned up

Two suspended packaged-app windows (Windows Security, a Calculator) minimised
under the old build are still parked at on-screen coordinates. They ignore
every cross-process restore route — `SW_RESTORE`, `WM_SYSCOMMAND`,
`SwitchToThisWindow` — and are cloaked, so nothing paints. Harmless and
invisible; they will go on the next reboot. The gate excludes cloaked windows
for exactly this reason.

### 6. What the gate still does not cover

Z-order is separate and slower (`test/bench/win-latency/zorder-stress.ps1`,
0/24 expected, passed today). Nothing checks that anything LOOKS right beyond
"pixels have variety" — the screenshot it keeps on every run is for human
eyes. Multi-monitor is untested everywhere.

The gate itself had a check that could not fail — it asked whether explorer's
desktop was on screen in a way that always answered no, and it asked about the
tray using a window class this shell takes for itself. Both fixed in
`fa2f00f`; worth assuming there are others, and worth testing a gate check by
breaking the thing it guards.

## Traps worth not re-learning

- **A bench that identifies a window by class expires.** The Win+E rig looked
  for the file manager as its old process-per-window class, logged "window up:
  False" on all 20 reps, closed nothing between them, and measured a window
  that was already open — without failing.
- **`$null` is `""` to a PowerShell string argument.** It cost the gate its
  first run (a search for "any window class" became a search for a window
  whose class is the empty string), it cost a build-and-verify round here (a
  probe reported explorer had no desktop window when it plainly did), and it
  had left one gate check permanently incapable of failing. Three times now.
  There are `Find(title)` and `FindClass(cls)` helpers in the gate that cannot
  be called wrongly — use them, and never hand `$null` to a P/Invoke string.
- **Nested value-type assignment from PowerShell silently does nothing.**
  `$d.rc.R = 3840` on a struct inside a struct leaves it zero, with no error,
  so a probe that "registered an appbar" registered an empty rectangle and
  concluded the shell was broken. Build the struct in the C# helper and assign
  it whole.
- **Two shells at once make every measurement meaningless, and it is the
  default outcome.** Killing the shell to restart it races Winlogon's own
  respawn, and a driving script that then starts one of its own ends up with
  two supervisors and two docks. A work-area check under that reads as a
  failure of the code. Kill, wait, kill again, and assert exactly one
  supervisor before measuring anything.
- **Killing a packaged app orphans its frame.** The window belongs to
  `ApplicationFrameHost`; kill the app and an empty white frame stays on the
  desktop, over whatever the next screen check is photographing. Close it.
- **Screenshots are downscaled on the Windows side.** Two full 4K PNGs filled
  the driving session's scratch directory and took its tooling down with it.
