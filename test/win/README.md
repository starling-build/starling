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

| check | the bug it would have caught |
|---|---|
| the five session processes | a supervisor that refused to start, or two shells fighting over one screen |
| explorer alive, owning no chrome | packaged apps that will not launch; explorer's taskbar or desktop showing over ours |
| the dock reserves its strip | maximized windows running underneath the dock, with the dock still drawn |
| the desktop surface is on screen | a black screen with a dock on it — every number green, no wallpaper |
| the shell holds the minimize target | minimized apps left as title-bar stubs sitting on the dock |
| a minimized window leaves the screen | the same, from the app's side |
| the file explorer opens, minimizes, comes back | Files minimized into nowhere, unreachable by any route |
| a packaged app launches, minimizes, comes back | Calculator and the Store dying two seconds after launch |

Every row is a bug that actually shipped, which is the bar for being in here.

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

The probe window is destroyed, the file explorer is put back to the
visibility it had, and the Calculator used for the launch check is closed. A
failing run may leave an app open — that is deliberate, so the state can be
looked at.
