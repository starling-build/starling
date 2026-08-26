# Checkpoint — Windows shell, 2026-08-25 (late night)

Where the Windows shell stands, what is verified, and every issue found that is
not fixed. Written so the next session can start from evidence rather than from
scratch. Supersedes this evening's version; the parts still true are folded in.

Box: the physical machine (`starling@192.168.68.60`), running mainline as the
registered `Winlogon\Shell` with autologon. Mainline is pushed through
`b12ed96`. Box left clean: five shell processes plus one hidden service
explorer, wallpaper up, gate 9/10 (the failure is the known console stub).

**Headline: packaged apps now open reliably, and the answer was to stop being
clever.** The borrow-per-launch design — start an explorer for the activation,
kill it, idle with none — was this morning's pride and tonight's casualty. It
fell apart under a repeat harness, for reasons measured in detail below. The
explorer service is ON BY DEFAULT again (`b12ed96`): one hidden explorer for
the whole session, ~227 MB and 0.05% of a core. Settings opens in **0.5 s**
(the borrow's best day was 1.1 s), twelve consecutive launches framed
correctly on a cold boot, and the desktop keeps painting.

## What landed and is verified

| | commit | verified by |
|---|---|---|
| Explorer service default-on; borrow only as fallback | `b12ed96` | 12/12 launches framed on a cold boot; explorer stays 1; desktop paints |
| Hand-back waits for the app's window, not a timer | `b12ed96` | trace shows the wait; explorer never leaked (one-shot launcher now waits for the hand-back thread) |
| Frame probe matches by TITLE, the association that exists | `b12ed96` | the pid-in-child-tree version never matched one healthy frame |
| Investigation knobs | `b12ed96` | `STARLING_NO_PRIME=1`, `STARLING_BORROW_CLEAN_EXIT=1` (untested cure, kept) |

Numbers to compare against: Settings **0.5 s**, Calculator **0.4 s**, launcher
exit to frame-on-screen, service explorer alive. Idle: shell ~0.3% / 142 MB,
explorer 0.05% / 227 MB.

## Why the borrow died — the evidence, so nobody rebuilds it

The frame a CoreWindow app lives in (Settings, Calculator, the Store
generation) is built by shell machinery that exists only while an explorer
runs. Cycling explorers — start one, activate, TerminateProcess — left that
machinery **flapping**:

- **In one session, four consecutive launches went frame, no-frame, frame,
  no-frame** — with which binary did the launching A/B-ruled-out as the
  variable. A launch on the wrong beat is a full-screen
  `Windows.UI.Core.CoreWindow`, `cloaked=2`, running and invisible, with no
  frame ever coming.
- **The same cycling blacks out our own desktop view** for the rest of the
  session. Pixel-verified repeatedly; only a reboot clears it. It appears the
  first time an explorer is started-and-killed next to the running shell and
  never heals.
- **A session soaked in explorer kills degrades further**: borrowed explorers
  stop completing their own startup (StartMenuExperienceHost activation fails
  `0x80040905`), and eventually even a full, visible, hand-started explorer
  cannot get frames built. Reboot clears it. Under native explorer-as-shell
  the same machine frames instantly — the damage is session-scoped and ours.
- Ruled out along the way, each by a controlled boot: the hand-back timing
  (waiting 30 s with explorer alive changed nothing), the logon prime, a
  20-second "warm-up" explorer killed before launching (the machinery does
  not persist a kill), and a pending Windows OOBE nag (below).

Why it looked fine when it landed: those first measurements ran in a session
where the service-era explorer had been alive for hours — warm machinery,
every launch framed — and the "sometimes no frame" note was already the
flapping, misread as a hand-back race.

## Two measurement traps that cost most of tonight

- **The frame is associated to the app by TITLE, never by child windows.** An
  `ApplicationFrameWindow` belongs to ApplicationFrameHost and mirrors the
  app's title; the app's CoreWindow stays a TOP-LEVEL window, cloaked by the
  shell, **even when perfectly framed**. A probe that looked for the app's
  pid in the frame's child tree ("adoption is a reparent") never matched a
  healthy frame once — every launch read as broken, including working ones,
  which manufactured "25 consecutive failures" and sent the whole
  investigation down a session-poisoning rabbit hole. Match `title +
  class=ApplicationFrameWindow`, like the gate does.
- **A colour-variety check cannot tell a black screen from a white one.** The
  desktop-black verdicts survived (screenshots confirmed), but variety=1 also
  matches an orphaned white frame. When the verdict matters, screenshot with
  the app OPEN and look.

Also re-learned: **a stale `.done` sentinel makes a wait return instantly** —
delete it and VERIFY the delete before `schtasks /run` (it bit twice; a del
right after boot failed silently); **PowerShell captures function output into
the assignment** — a `"label: $x"` line inside a function becomes part of the
return value and the string makes any boolean truthy; `Write-Host` for logs
inside functions; **deploy-main.ps1 overwrites its own backup** — the bisect
was saved by an older `WinShellBar-old-1.exe` sitting in `C:\dist\Starling`.

## The Windows OOBE discovery (not the frame bug, but real)

Windows scheduled its full-screen "back up your PC" second-chance-OOBE nag
for this user sometime today. Under explorer it displays at logon (screenshot
in `C:\dist\scoobe-1.png`'s era); under our shell nothing hosts it, so it sits
pending forever. It turned out NOT to be the frame blocker (dismissing it
changed nothing), but a session that can never show a pending OOBE experience
is a standing risk. On the box it is dismissed and disabled
(`HKCU\...\UserProfileEngagement\ScoobeSystemSettingEnabled=0`). A shell
defense — setting that key for the session user, or hosting the nag — is an
open design question.

## Open issues

1. **The console stub on a cold boot** — gate 9/10, unchanged, pre-existing:
   the supervisor's Windows Terminal console window sits minimized on screen.
   The title-based hide misses this boot path.
2. **The flapping mechanism is described, not explained.** Why alternate?
   What exactly does a TerminateProcess'd explorer leave behind that the next
   one trips over, and what does the black desktop share with it? Moot under
   the service, but it bounds how safe ANY explorer kill is — including
   crash-recovery paths. `STARLING_BORROW_CLEAN_EXIT=1` (ask explorer to
   leave via `WM_USER+436` to its tray before terminating) is implemented and
   completely untested; it is the first thing to try if this is ever
   reopened.
3. **Win+E latency re-baseline** — still owed; the ground moved again (a
   service explorer is back).
4. **Deploying races Winlogon's respawn** — unchanged from this morning's
   checkpoint: the deploy script kills and re-stages, a second supervisor
   stands down, but nothing in the tree enforces the rename-and-re-register
   pattern.
5. **Gate coverage** — z-order is separate and slower; nothing checks how
   things LOOK beyond pixel variety; multi-monitor untested everywhere.

## Box state changed tonight (so the next session isn't surprised)

- Explorer service running by default; `HKCU Winlogon\Shell` = our shell.
- `ScoobeSystemSettingEnabled=0` set; the OOBE backup nag dismissed.
- `STARLING_NO_PRIME` removed from the user environment (was set mid-bisect).
- `C:\dist\bk\WinShellBar-old.exe` no longer holds yesterday's binary.
- Reusable harness: `C:\dist\borrowloop.ps1` (+ `StarBorrowLoop` task) — 12
  launches, title-based frame check, explorer count, desktop variety.

## Dead ends, kept from the previous checkpoint (all still true)

- Implementing explorer's immersive-shell COM component ourselves: past its
  first method lies the next; proxy in OneCoreUAPCommonProxyStub, impl in
  twinui.dll.
- `explorer.exe /factory,{CLSID}`: registers the class, exits, never serves.
- `FreeConsole` for the console stub: takes the session down, 0/10.
- `SetTaskmanWindow` / `SetShellWindow` for minimize placement: not the
  switch; only a shell having come up flips it (the logon prime does this).
- A refused activation does not fail fast: 45141 ms, twice, to the
  millisecond. Check services are up BEFORE activating.
- Never `Stop-Process WindowsTerminal` on the box (hosts the supervisor's
  console). The crash-loop bail UNREGISTERS the shell — if the box boots to
  explorer, run `WinShellBar.exe --register-shell` and reboot.
