# The Windows shell gate

One command, run from here, that says whether the Windows shell on the
physical box is in a shippable state:

```bash
test/win/run-gate.sh                          # the usual box
STARLING_WIN_HOST=user@host test/win/run-gate.sh
```

It exits 0 when every check passes, prints what failed when they don't, and
brings back a screenshot of the failing screen.

## Two places to run it

`run-gate.sh` drives the **physical box** over SSH, against the staged tree.
`run-gate-vm.sh` drives a **libvirt VM** through the QEMU guest agent, against
an INSTALLED package — no SSH, files in over HTTP from the host:

```bash
test/win/run-gate-vm.sh -d win11-gate --install dist/StarlingSetup-0.1.0.exe
test/win/run-gate-vm.sh -d win11-gate          # gate what is already installed
```

The VM is the honest environment for a release: the dev box has the toolchain,
an engine checkout and a staged tree on it, so it cannot say whether the
*package* works. `docs/WINDOWS-INSTALL.md` covers making a clean VM; run the
gate on a copy-on-write overlay so the clean box stays clean.

**Everything the VM caught the first time it ran was a bug in the GATE, not in
the shell** — and each was a "works on my 4K screen" assumption:

- the dock-strip check demanded 60 px. The dock is 56 *points*, so it reserves
  112 px at the dev box's 200% and exactly 56 at a VM's 100%; a correct
  reservation failed. It scales with the display now (`ExpectedStrip`).
- the context menu **flips upward** when it will not fit below the cursor, so
  on a short screen its bottom edge lands *on* the click and "the popup under
  the cursor" finds the window behind it. Adjacency, not containment.
- Calculator was graded blank because our own file explorer was on top of it:
  grabbing the screen at a window's rect grades whatever covers it. The check
  now confirms the app owns its own centre first, and moves OUR window if not.
- and the blankness threshold itself was 25 distinct colours, measured on a
  large antialiased 4K Calculator. A perfectly drawn one on a 1280x800
  software-rendered VM has 19. It is 10 now, which is still far from the two
  or three a window that never painted produces.

## What it checks, and why each one is here

| check | looks at | the bug it would have caught |
|---|---|---|
| the five session processes | handles | a supervisor that refused to start, or two shells fighting over one screen |
| explorer alive, owning no chrome | handles | packaged apps that will not launch; explorer's taskbar or desktop showing over ours |
| the dock reserves its strip | the work area | maximized windows running underneath the dock, with the dock still drawn |
| the desktop surface is on screen | handles | nothing drawing a wallpaper |
| there is a wallpaper, not a black screen | **pixels** | a black screen with a dock on it — every handle correct, nothing drawn |
| the dock is drawn along the bottom | **pixels** | a reservation that holds while the dock itself never paints |
| the session parks minimized windows off screen | a system metric | minimized apps left as title-bar stubs sitting on the dock — and the check it replaced, which asked who owned the taskman slot and failed Windows 10 for a slot nobody there ever claims |
| a minimized window leaves the screen | handles | the same, from the app's side |
| the file explorer opens, minimizes, comes back | handles + **pixels** | Files minimized into nowhere; and a restored window that comes back blank |
| a right-click opens its context menu | handles + **pixels** | a file manager with no menu at all, and the menu that opens as a blank panel — the popup is a real window, so this is a window check with a paint check on top |
| the listing shows what is on disk | the probe | a file manager that opens onto nothing |
| the context menu offers the verbs its buttons invoke | the probe | Cut/Copy/Delete/Share drawn as pictures of buttons, because the shell stopped offering the verb behind one |
| copy / move / rename, and their undos | the probe | an operation that reports success and does nothing; a Ctrl+Z that puts the file back in the wrong folder or under the wrong name |
| Copy/Cut + Paste through the clipboard | the probe | a paste that copies when it should move, or a cut that leaves the original behind |
| Delete recycles, and Ctrl+Z restores | the probe | a "delete" that destroys instead of recycling — the one operation whose undo cannot be written afterwards |
| New folder, Compress to ZIP | the probe | the two menu rows that create something, silently creating nothing |
| a packaged app launches, minimizes, comes back | handles + **pixels** | Calculator dying two seconds after launch; and an empty frame that passes for a running app |
| the dock knows which app a packaged window is | the shell's own answer | every Store app getting a SECOND dock tile instead of lighting its pinned one — with Settings and Calculator sharing that tile, because both frames belong to ApplicationFrameHost |
| the chrome refuses a bare WM_CLOSE, and logs it | an attack + the log | the silent restarts: the chrome obeyed any close, exited code 0, and the session restarted under the user ~15 times in 36h with no crash log to show for it |
| SC_CLOSE (Alt+F4's road) bounces off too | an attack | the same, through the door every real close actually takes |
| the desktop surface refuses a close | an attack | a wallpaper plane anyone could destroy with one posted message |
| an overlay dismisses on close instead of dying | an attack | an overlay process death where the user meant "close this flyout" |
| a second --session stands down, and says so | the log | the silent-refusal respawn: a --session that exits without writing a line is how a machine sat shell-less on explorer for seven minutes |
| a killed chrome comes back, and the death is named | a kill + the logs | recovery: respawn within 45s, the strip re-reserved, an exit CODE in session.log, and the dying run's log preserved — a death without forensics is the 08-27 hunt again |

Every row is a bug that actually shipped, or one the file explorer has no
other guard against, which is the bar for being in here.

## The file explorer rows, and what they honestly cover

The operation rows are driven by `WinShellBar.exe --files-probe`, which runs
the whole set against a throwaway directory under `%TEMP%` and prints a line
per feature. The gate runs it **once** and each row reads that output, so a
red gate names the feature rather than one lump called "files".

It calls the operations at the C boundary, like `--fileop-probe` does, and not
through `Win32FileOps`: that wrapper answers on `DispatchQueue.main`, a
console process has no main run loop to deliver it, and every step would time
out. What the wrapper adds over that boundary is dispatch and journal
decoding, both of which the probe does itself.

**What this does not prove: that clicking the "Copy" pill dispatches a copy.**
That wiring is Swift-side, between `FilesMenu` and `FilesBloc`; the probe
proves the operation works and that the shell still offers the verb the pill
invokes, and the right-click row proves the menu opens and paints. Closing
that last gap needs a driver that can click a cell *inside* a Flutter view,
which this gate does not have — so it is stated here rather than implied by a
row that sounds stronger than it is.

Both new rows were falsified rather than trusted for being green:

- with the Files window hidden, the right-click lands on the desktop, no
  popup opens, and the row fails — so it is not passing on some other
  window's menu. It now asserts the click point is over Files, that Files
  holds the foreground, and identifies the menu by `WindowFromPoint`.
- feeding the gate's parser a doctored probe output fails the row three ways:
  a step that reported FAIL (carrying its reason), a step missing from the
  output, and a probe that never ran.

**Identify a menu by what is under the cursor, never by class alone.** Popup
surfaces are pooled and reused, so a run that dies mid-menu leaves one behind:
still `WS_VISIBLE`, not cloaked, sitting behind the Files window where nothing
draws it. The first spelling of this row asked "is any popup visible", found
that ghost *before the click had even happened*, and then reported a menu that
would not close — while the real menu closed fine. `WindowFromPoint` cannot
make that mistake: a covered window is never the answer.

**Dismissal is asserted on the FIRST Escape, and that assertion is what
found the bug this row exists for.** It was briefly relaxed to a click-away
while the cause was unknown: menus reliably needed two Escapes. The cause
turned out to be two of them. An inline rename that a click never ended left
a focused field eating the first Escape; and the file explorer's whole
keyboard died whenever its window was hidden and brought back, because
`PlatformDispatcher.onKeyData` is one slot and the desktop surface in the
same process assigned it too (see `docs/plans/winshell-tasks.md`). Both are
fixed, and asserting the first Escape is what keeps them fixed.

**The foreground assertion is load-bearing, not tidiness.** The menu is
`WS_EX_NOACTIVATE`, so its keyboard is handled by the host window — a stray
app holding the foreground eats the keystroke. A leftover Notepad from another
test made this row report a menu that would not close on Escape, before the
real Escape bug above was isolated.

The last six rows are the **survival section**: the earlier checks ask whether
the steady state is right, and none of them ever attacked the shell — which is
exactly where the silent-restart bug lived. The kill check guards itself: it
skips when a chrome exit happened in the last 90 seconds, because the
supervisor hands the desktop to explorer on the second exit inside a minute,
and two gate runs back to back must not do that to a machine.

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
