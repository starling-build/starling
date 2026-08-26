# Checkpoint — Windows shell, 2026-08-25 (end of day)

Where the Windows shell stands, what is verified, and every issue found that is
not fixed. Written so the next session can start from evidence rather than from
scratch. Supersedes this morning's version; the parts still true are folded in.

Box: the physical machine (`starling@192.168.68.60`), running mainline as the
registered `Winlogon\Shell` with autologon. Mainline is pushed through
`3dac693`. Box left clean: five processes, no explorer, wallpaper up.

**Headline: the shell no longer keeps an explorer running.** Native Settings and
Calculator launch in about a second on a machine with none. That was the day's
goal and it works — but issue 1 is a real weakness in HOW it works, and is the
first thing to pick up.

## What landed and is verified

| | commit | verified by |
|---|---|---|
| The dock's strip stays reserved with explorer alive | `d2c8c75` | both configurations; maximized window stops at the dock |
| An unrecognised flag is refused, not run as the dock | `618e098` | `--hide-taskbar` exits 2 instead of starting a second shell |
| Native Settings with no permanent explorer | `d94a4bb` | 1.1 s on a machine running none; explorer gone afterwards |
| One shell per session, not one more each time | `fed917b`, `45edc7d` | supervisor restarts leave one dock; a second stands down |
| Minimized windows leave the screen | `45edc7d` | cold boot, probe parks at −32000 |
| The console stub in the corner is gone | `45edc7d` | cold boot, stub check clean |
| The gate checks the shell that exists now | `cef0b87`, `3dac693` | 9/10 on a cold boot |

Numbers to compare against: Settings **1.1 s**, Calculator **0.9 s**, Windows
Terminal **0.5 s**, each launched through the shell with no explorer running.
Idle: **no explorer at all**, where it was 227 MB permanently before.

## How packaged apps work now, in one paragraph

Apps of the CoreWindow generation — Settings, Calculator, the older Store
generation — cannot be ACTIVATED unless explorer is running: it publishes a
background COM component the activation machinery asks for by identity, and
without it the launch is refused outright and the app process is never created.
They do not need it once running. So the shell borrows an explorer for the
launch and drops it. Measured: activation succeeds 1.2 s after starting one, and
killing it afterwards leaves the app working indefinitely.

**A refused activation does not fail fast — 45141 ms, twice, to the
millisecond.** That is a DCOM activation timeout, not work, and it is why the
shell asks whether the services are up BEFORE activating rather than activating
and recovering from the refusal. Try-then-recover cost 53 seconds a launch.

## Open issues

### 1. A borrowed explorer sometimes leaves the app invisible and the desktop black — the blocker

**Symptom, both halves together, and only sometimes.** A packaged app launched
through the borrow comes up with no `ApplicationFrameWindow` at all: a
full-screen `Windows.UI.Core.CoreWindow`, `cloaked=2` (cloaked by the shell) —
running, and completely invisible. In the same runs the **desktop goes black**:
our own desktop view stops painting, and nothing is covering it, since our two
full-screen windows are still the only ones there. A reboot clears both.

**What is ruled out.** Not restore-from-minimized — a framed app restores every
time, measured by hand with and without an explorer, so the gate's old
"restore=False" was a measurement bug and is fixed (`3dac693`). Not the
Start/Search hosts a borrowed explorer brings up: killing them changes nothing.
Not the work area, which holds correctly through launches.

**What was tried.** Widening the hand-back grace from 3 s to 10 s. Did not fix
it.

**Next move.** Hand explorer back only once the launched process actually HAS a
visible, uncloaked window, rather than after a fixed delay — the frame is built
by ApplicationFrameHost in concert with the shell, and a fixed timer is racing
that. If that does not hold it, the honest fallback is the permanent explorer,
which had none of these symptoms at 227 MB.

### 2. Win+E latency: 146 ms against 110 ms recorded — unmeasured, not unchanged

One 33 ms frame apart, and the rig's own rule is that anything under two frames
is unmeasured until it survives a proper A/B. Still not done, and the ground has
moved: there is no permanent explorer now, so re-baseline rather than comparing
against the old number.

### 3. Deploying races Winlogon's respawn

`AutoRestartShell` is on, so killing the shell to swap the binary gets a new one
started within a second. The deploy scripts on the box rename the running exe
rather than overwriting it, and re-register the shell afterwards, but nothing in
the tree enforces it. Far less dangerous than it was — a second supervisor now
stands down instead of fighting — but a deploy that skips the re-registration
can still leave the box booting explorer.

### 4. What the gate still does not cover

Z-order is separate and slower (`test/bench/win-latency/zorder-stress.ps1`,
0/24 expected). Nothing checks that anything LOOKS right beyond "pixels have
variety" — the screenshot it keeps every run is for human eyes. Multi-monitor is
untested everywhere. And the gate has now had three checks that could not fail
or asked the wrong question: assume there are more, and test a gate check by
breaking the thing it guards.

## Traps worth not re-learning

- **Never `Stop-Process WindowsTerminal` on that box.** It hosts the
  supervisor's console, so killing it kills the shell and the session ends up
  showing explorer's taskbar. Done twice in one day, both times while "cleaning
  up leftovers".
- **The crash-loop bail UNREGISTERS the shell.** If the box boots to explorer,
  that is what happened: run `WinShellBar.exe --register-shell` and reboot.
- **A reaper that cannot tell a child from another supervisor is a boot loop.**
  Every role is the same binary. Two supervisors reaped each other's children,
  each saw them die and restarted them, the crash-loop arithmetic fired, and the
  desktop went back to explorer — a new session every thirteen seconds. Children
  now mark themselves with a named event; the supervisor is single-instance on a
  named mutex.
- **A job object is the wrong way to make children die with the parent.**
  Everything a child starts joins the job too, so quitting the shell would take
  the user's browser with it.
- **`$null` is `""` to a PowerShell string argument.** Four times now: it cost
  the gate its first run, it left a gate check permanently incapable of failing,
  and it cost a build-and-verify round here by reporting that explorer had no
  desktop window when it plainly did. Use the gate's `Find(title)` /
  `FindClass(cls)` helpers; never hand `$null` to a P/Invoke string.
- **Nested value-type assignment from PowerShell silently does nothing.**
  `$d.rc.R = 3840` on a struct inside a struct stays zero, with no error — a
  probe that "registered an appbar" registered an empty rectangle, and I
  concluded the shell was broken. Build the struct in the C# helper, assign it
  whole.
- **Measure in the process that owns the thing.** Several fixes and one oracle
  were run in a throwaway launcher process with no dock, no tray and no appbars,
  so they answered questions about the harness. If the answer depends on the
  dock, ask the dock: cross-process, `ABM_GETTASKBARPOS` tells you whether the
  dock's registration landed in our own appbar service.
- **Two shells at once make every measurement meaningless**, and it used to be
  the default outcome of a restart — it reached five docks. Assert exactly one
  supervisor before measuring anything, even now.
- **A bench that identifies a window by class expires.** The Win+E rig looked
  for the file manager by its old class and measured a window that was already
  open, without failing.
- **A packaged app has TWO windows with the same title** — its own drawing
  surface and the frame hosting it — and the surface can appear first. Only the
  frame answers a restore from another process.
- **Killing a packaged app orphans its frame**: the frame belongs to
  `ApplicationFrameHost`, and an empty white rectangle is left over whatever the
  next screen check photographs. Close it.
- **Screenshots are downscaled on the Windows side.** Two full 4K PNGs filled
  the driving session's scratch directory and took its tooling down with it.

## Dead ends, recorded so nobody spends the day again

- **Implementing the immersive shell ourselves.** The component explorer
  publishes is `C2F03A33-21F5-47FA-B4BB-156362A2F239`, registered at runtime
  with no LocalServer32, and activation asks it for exactly one service,
  `848eaf0a-4435-4d6f-bcdf-8f42ffb38400` — unnamed, undocumented, proxy in
  `OneCoreUAPCommonProxyStub.dll`, implementation in `twinui.dll`. You CAN
  register a stand-in for the class — proven, Windows accepted it and called
  into it — but getting past its first method only reveals the next.
- **`explorer.exe /factory,{CLSID}`.** Comes up at 71 MB instead of 221 and
  registers the class, then exits and never serves it.
- **`FreeConsole` to be rid of the supervisor's console.** Takes the whole
  session down: 0 of 10 checks, nothing on screen at all.
- **`SetTaskmanWindow` / `SetShellWindow` for minimize placement.** We already
  hold the taskman window — a stranger asking for it is refused — and claiming
  the shell window changes nothing. Only a shell having come up flips it, which
  is why the supervisor now runs an explorer for two seconds at logon.
- **Only the CoreWindow generation needs any of this.** Full-trust packaged apps
  (Windows Terminal, Dev Home, Photos, Quick Assist) launch with no explorer at
  all. If the borrow is ever abandoned, that is what would still work.
