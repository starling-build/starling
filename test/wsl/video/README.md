# Recording the WSL walkthrough

`ui/video/wsl-walkthrough.mp4` — how to run the Starling desktop on a Windows
machine through WSL, recorded end to end on the real box. Nothing in it is
faked or sped up: the `.deb` really installs, the desktop really starts, and
Windows' own Remote Desktop really connects to it.

    scp <the .deb> starling@<box>:C:/dist/            # under its OWN name
    scp test/wsl/video/take.ps1 test/wsl/video/take.vbs starling@<box>:C:/dist/vid/
    ssh starling@<box> 'schtasks /create /tn StarVidTake /ru starling /it /sc once /st 00:00 /tr "wscript.exe C:\dist\vid\take.vbs" /f'
    ssh starling@<box> 'schtasks /run /tn StarVidTake'
    # then fetch C:\dist\vid\wsl-walkthrough.mp4 and marks.txt

An **interactive scheduled task**, because ssh lands in session 0, which has
no desktop — the same reason `test/win/run-gate.sh` does it.

The take **purges the package first, off camera**, so the install the viewer
watches is a real one: `apt` treats a `.deb` whose version is already
installed as nothing to do, and would print a no-op.

## Nine things that cost takes

- **`Type` is a built-in PowerShell alias for `Get-Content`**, and aliases beat
  functions in PowerShell's resolution order. A helper called `Type` is never
  called and every "typed" line silently does nothing. It is `TypeText` here.
- **Never kill ffmpeg to stop recording.** A killed encoder does not write the
  moov atom and the mp4 is unplayable. Give `-t` the take's length and wait for
  it to exit on its own.
- **mstsc will not be moved.** `MoveWindow` returns true and the session window
  snaps straight back to the screen's top-left — 25 attempts, same answer. So
  the capture region is placed where it lands rather than the other way round.
- **Capture a 1920x1080 region, not the 4K screen scaled down.** Scaling 4K
  into 1080p makes console text unreadable, and console text is the content.
- **Clicking a taskbar tile while Start is open only dismisses Start** — the
  click never reaches the tile. Send Escape first, then click.
- **`powershell.exe` opens Windows Terminal on Windows 11**, which honours
  neither `MoveWindow` nor `HKCU\Console` — so the console lands where it
  likes at a font nobody chose. Launching `conhost.exe` directly does not
  help: it hands the window off and the process you get back never owns one.
  Set `DelegationConsole`/`DelegationTerminal` under `HKCU\Console\%%Startup`
  to the conhost CLSID, then a plain `powershell.exe` gives a classic console
  that obeys both.
- **`-32000,-32000` is where Windows parks a minimized window.** A placement
  loop that finds "the first console with a title" can pick up a *minimized
  leftover from the previous take*, scrollback and all, and dutifully restore
  it. Kill old consoles first and match the process you started, by id.
- **Copy the .deb under its own name.** An early cut showed
  `dpkg -i starling-gate.deb`, which was only the filename the gate happened
  to scp to -- and it made a perfectly ordinary Debian package look like some
  special build. It is `apt install /path/starling_<ver>_amd64.deb` now, which
  is what a person would actually type.
- **The taskbar moves with the session size**, so click coordinates cannot be
  hardcoded from one resolution to another. The Fluent row is centred: for a
  WxH session the first tile is at `(W/2 - 182, H - 28)` and tiles are 52
  apart, which reproduces exactly what the desktop reports for itself.

Coordinates come from the desktop rather than from measuring pixels: the agent
broker's `dock_rects` reports each tile's centre in the session's own
coordinates, which map 1:1 onto the RDP surface. Ask it once at the session
size you are recording at, or use the formula above.

The session is **1920x1080**, and the finished video is cropped to exactly the
Remote Desktop client area — so what you watch is the remote screen itself,
1:1, with no scaling anywhere in the chain.

Every `wsl.exe` launch steals the foreground, and once mstsc has lost it the
session looks frozen though it is fine — so all the WSL work happens before
Remote Desktop opens, and nothing touches `wsl.exe` after.
