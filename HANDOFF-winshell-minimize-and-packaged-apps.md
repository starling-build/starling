# Checkpoint — Windows shell, 2026-08-25

Where the Windows shell stands after the minimize / packaged-app work, what is
verified, and every issue found along the way that is not fixed. Written so
the next session can start from evidence rather than from scratch.

Box: the physical machine (`starling@192.168.68.60`), running mainline as the
registered `Winlogon\Shell` with autologon. Mainline is pushed through
`406dcd4`.

## What landed and is verified

| | commit | verified by |
|---|---|---|
| Minimized apps stop leaving title-bar stubs on the desktop | `f9bcb0a` | probe minimize parks at −32000; matches native measured the same night |
| The file explorer comes back from minimized | `54379bb` | Win+E → minimize → Win+E, window returns painted |
| Packaged (Store) apps can run, **opt-in** | `a358345`, `1d2528b` | Calculator activates, shows, minimizes, restores |
| A repeatable Windows gate, 10 checks, 4 of them pixel | `222eca7`, `8b8aae8` | 10/10 twice; 8 passed + 2 skipped in the shipping configuration |
| Idle CPU regression found and fixed; perf re-measured | `406dcd4` | 60 s idle sample; 20-rep latency capture |

Numbers, for comparison next time: idle **0.31%** of one core / 142 MB for the
shell (of which banners' notification poll is 0.26%), explorer **0.05%** /
227 MB when the service is on, dwm 0.00%. Win+E → file explorer drawn,
**median 146 ms** over 20 reps, arriving fully painted in one frame.

## Open issues

### 1. The work area, with the explorer service on — the blocker

**Symptom.** With `STARLING_EXPLORER_SERVICE=1`, after a shell restart, the
dock's strip is not reserved: the work area is the full screen height, the
dock still draws, and maximized windows run underneath it. Reproducible by
restarting the shell while explorer is alive — which is also what a crash
respawn and every deploy do.

**What was tried, and did not hold it.** Re-assert the appbar at startup;
re-assert on explorer's `TaskbarCreated` broadcast; a self-healing watcher
that re-registers whenever the work area disagrees with the strip; all three
together. Each is in the tree and each is individually correct — none is
sufficient.

**The tell.** Re-registering is not the missing piece. The reservation appears
only when something makes explorer recompute of its own accord: activating a
packaged app did it once, minutes after a gate run had already failed on it.

**The likely cause.** Our tray owns the `Shell_TrayWnd` class, so
`SHAppBarMessage` resolves to US, not explorer — measured, both windows exist
and `FindWindow` returns ours first. With explorer alive there are two shells
computing the work area and explorer wins.

**Next move.** Own the work area explicitly in the appbar service
(`SPI_SETWORKAREA`) rather than asking whoever answers `SHAppBarMessage` to do
it, and re-apply when explorer stomps it. Until then the service stays
opt-in and `test/win/run-gate.sh` skips its two checks.

### 2. Win+E latency: 146 ms against 110 ms recorded — unmeasured, not unchanged

One 33 ms frame apart, and the rig's own rule is that anything under two
frames is unmeasured until it survives a proper A/B. The A/B that would settle
it is the same capture with the explorer service off; it was set up and not
completed. Do that before believing either number.

### 3. An unrecognised command-line flag starts a whole second shell

`WinShellBar.exe --hide-taskbar` — a flag that does not exist — fell through
every branch in `main.swift` into the **dock** branch and ran a complete
second shell chrome, which then fought the real one for the taskman window
(`minimize target taken: false` in its log) and had to be killed by hand.
Anything mistyped does this. `main.swift` should refuse an argument it does
not recognise instead of defaulting to "be the dock".

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

## Traps worth not re-learning

- **A bench that identifies a window by class expires.** The Win+E rig looked
  for the file manager as its old process-per-window class, logged "window up:
  False" on all 20 reps, closed nothing between them, and measured a window
  that was already open — without failing.
- **`$null` is `""` to a PowerShell string argument.** It cost the gate its
  first run (a search for "any window class" became a search for a window
  whose class is the empty string) and it is recorded in the tree twice
  already.
- **Killing a packaged app orphans its frame.** The window belongs to
  `ApplicationFrameHost`; kill the app and an empty white frame stays on the
  desktop, over whatever the next screen check is photographing. Close it.
- **Screenshots are downscaled on the Windows side.** Two full 4K PNGs filled
  the driving session's scratch directory and took its tooling down with it.
