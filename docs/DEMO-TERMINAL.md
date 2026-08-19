# Demo runbook — the terminal on macOS, with subtitles

Makes a ~100 s screen recording of Starling Terminal: panes, an agent running
in one of them, a workspace over ssh, the link breaking and replaying, and the
whole arrangement surviving a full quit and reopen. Captions are burned in
afterwards from a beat log the driver writes as it goes.

This is the macOS terminal's counterpart to `docs/DEMO.md`, which films the
Linux desktop. Nothing here is staged: it is a real session against a real
host, and the link really is cut mid-take.

Tools: `build/tools/terminal-demo/` — `drive.py` (drives and logs beats),
`captions.py` (burns them in), `click.swift` (a CGEvent clicker `drive.py`
builds on first run).

---

## 0. Prerequisites

- A bundle to run: `build/macos-app.sh TerminalApp`. Drive the **bundle's
  binary**, not `open` — `open` cannot pass environment, and a remote
  workspace needs `STARLING_TERMD`.
- Accessibility **and** Screen Recording permission for whatever runs the
  scripts (Terminal, iTerm, the agent's shell). Keystrokes and
  `screencapture -v` fail differently and neither says why.
- A host to reach, with this branch's `starling-termd` built on it, and
  key-based ssh that needs no passphrase prompt.
- `ffmpeg` with `drawtext` (`ffmpeg -filters | grep drawtext`).
- For the agent beat, `claude` on `PATH`.

**`STARLING_TERMD` is the path on the FAR side.** One setting serves both ends
— `TermdPaths` has a single `server` — so when the demo opens a remote
workspace it must hold the remote path. Local *workspaces* then cannot resolve
it, which does not matter: ⌘T panes and ⌘D splits are plain ptys and never
touch termd.

## 1. Record

Launch, place the window, start the capture, drive it. Geometry is
load-bearing: `drive.py` clicks pane centres as absolute screen points, so a
window anywhere but (60,60) 1280x800 puts every click in the wrong pane.

```bash
OUT=/tmp/tdemo; mkdir -p $OUT
STARLING_TERMD=/home/you/termd/starling-termd \
  ".stage-macos/Starling Terminal.app/Contents/MacOS/TerminalApp" &
APP=$!; sleep 6
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $APP)
  set position of window 1 to {60, 60}
  set size of window 1 to {1280, 800}
end tell"

screencapture -v -V 115 -R 60,60,1280,800 $OUT/take.mov &
sleep 2                       # this is --lead in step 2
build/tools/terminal-demo/drive.py --out $OUT \
    --host you@box --ws demo --remote-termd /home/you/termd/starling-termd
```

**Start from a freshly launched app, every take.** Text left on a command line
from a previous attempt does not vanish — the next thing typed lands *appended*
to it, and you get `echo LEFT-PANEcd dev/starling && claude` running in the
wrong directory.

**Do not let a shell timeout kill `screencapture -v`.** A capture killed
mid-write wedges the login's ScreenCaptureKit layer: later captures hang, and
after force-killing the daemons even stills come back solid black. Only a
logout recovers it. Give the driving shell a timeout comfortably longer than
`-V`. It also cannot be started fully detached — it hangs at ~0% CPU — which is
why the recorder is a sibling of `drive.py` and not started by it.

## 2. Subtitles

```bash
build/tools/terminal-demo/captions.py $OUT/take.mov $OUT/beats.json \
    $OUT/demo.mp4 --lead 2.0 --end 105 --cover 30,1316,1245,60,#14161C
```

`--lead` is the gap between the capture starting and the driver starting;
without it every caption lands early by that much. Captions go in a bar padded
below the frame — an overlay covers terminal output wherever you put it.

**Cover what the apps put on screen that you would not publish.** Claude Code
prints the account's remaining weekly limit for the first seconds of a session.
`--cover` paints it out before padding. Sample the colour from the frame rather
than reading `TerminalTheme.background`: the window is translucent, so the file
holds the composite (`#14161C` for the shipped theme over black, not
`#171922`).

```bash
ffmpeg -ss 36 -i take.mov -frames:v 1 \
    -vf "crop=4:4:600:1290,scale=1:1" -f rawvideo -pix_fmt rgb24 - | xxd -p
```

## Traps

- **System Events cannot click a Flutter view.** `click at` reports a plausible
  target and does nothing; keystrokes are fine. Panes are focused by click and
  by nothing else — there is no keyboard binding for "next pane" — so any demo
  that puts different work in different panes needs `click.swift`. The first
  click on an inactive window is eaten by activation: pass a count of 2 when the
  app may not be frontmost.
- **⌘O prefills the last host, with a trailing slash.** Typing a full
  `host/ws:name` over it gives `host/host/ws:name`, which resolves to nothing.
  The only symptom is `[link lost — reconnecting…]` every couple of seconds
  forever — ssh's own error never reaches the pane — so a take can look like a
  product bug when it is a typing bug. `drive.py` clears the field first.
- **Claude Code asks about trust in a directory it has not seen**, and that
  prompt is the operator's to answer, not a demo's. `cd` into a checkout it
  already knows before launching it.
- **Arial has no ⌘ or ⇧.** They render as blank boxes, silently. `captions.py`
  uses Menlo, which has both and matches the terminal besides.
- **`pkill -x ssh` is the link break** — it takes every ssh on the machine, so
  do not hold one open elsewhere during a take. The workspace panes come back
  on their own; that is the point of the beat.
- **Batched chords race.** Several chords in one `osascript` block can leave a
  modifier stuck and make a working binding look dead. One chord per
  invocation, with a settle after it.
