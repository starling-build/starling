# Recording the WSL walkthrough

`ui/video/wsl-walkthrough.mp4` — how to run the Starling desktop on a Windows
machine through WSL, recorded end to end on the real box. Nothing in it is
faked or sped up: the `.deb` really installs, the desktop really starts, and
Windows' own Remote Desktop really connects to it.

    scp test/wsl/video/take.ps1 test/wsl/video/take.vbs starling@<box>:C:/dist/vid/
    ssh starling@<box> 'schtasks /create /tn StarVidTake /ru starling /it /sc once /st 00:00 /tr "wscript.exe C:\dist\vid\take.vbs" /f'
    ssh starling@<box> 'schtasks /run /tn StarVidTake'
    # then fetch C:\dist\vid\wsl-walkthrough.mp4 and marks.txt

An **interactive scheduled task**, because ssh lands in session 0, which has
no desktop — the same reason `test/win/run-gate.sh` does it.

## Five things that cost takes

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

Coordinates come from the desktop rather than from measuring pixels: the agent
broker's `dock_rects` reports each tile's centre in the session's own
coordinates, which map 1:1 onto the RDP surface.

Every `wsl.exe` launch steals the foreground, and once mstsc has lost it the
session looks frozen though it is fine — so all the WSL work happens before
Remote Desktop opens, and nothing touches `wsl.exe` after.
