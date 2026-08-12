# Demo runbook — workspace mode with an agent driving it

The demo: **workspace mode with Claude Code as the driver app**, and whatever it
opens — a browser, an editor, Blender — captured beside it as tabs. Two
workspaces, running independently.

This is a runbook, not a script. Every trap below cost real time the first time
through; they are in the order you will hit them.

Recorded on the NucBox (single AMD APU, no monitor attached) at a synthetic 4K
display. Everything here runs as the session user `starling` (uid 1001), not as
your login user.

---

## 0. Prerequisites

- The desktop deployed and running (`build/package-desktop.sh`, `dpkg -i`,
  `systemctl restart gdm`).
- Chrome, VS Code and Blender reachable. All three show up in the launcher on
  their own: everything in `registry/catalog.d` has a tile, and the registry
  counts an app as installed when a record exists **or** its binary is on disk
  (`installed: recorded || presentOnDisk`), falling back to the same
  freedesktop lookup `app-install` would have done. So `apt install blender` is
  enough to launch and identify it. `app-install --record blender` still pins
  the resolved `.desktop`, WmClass and version into
  `/var/lib/starling/installed.d/`, and is worth doing, but nothing in the demo
  waits on it.
- **Blender's launcher tile is a painted glyph, not the Blender mark**, and it
  is the only one on screen that is. Blender ships its icon as
  `hicolor/scalable/apps/blender.svg` and nothing else; both icon lookups
  (`find_icon` in `build/app-install.sh`, `DesktopEntry.swift` in `registry/`)
  take PNG/JPG at fixed pixel sizes, and the shell decodes through the Flutter
  image codec, which has no SVG. Nothing to do about it on the day — the
  fallback tile is deliberate, since third-party marks are never shipped.
- `sudo` on the box (shell-drive needs `/dev/uinput` and signals the shell).

## 1. Give it a display

**On the Lenovo dev box, skip this section** — it has a real 2560x1600 panel
(`eDP-1`) and usually a real 4K Dell on `HDMI-A-1`, and the session picks them
up by itself. Do **not** force connectors there, and never write to `eDP-1`'s
`status`: that is the user's screen, and `off` blanks it until they reboot. See
CLAUDE.md, "This dev box has a real display".

Only on a genuinely headless machine — nothing `connected` anywhere — hand an
unused port a synthetic EDID. 4K is worth it: more room for the three columns,
and it exercises the fractional-scale path at 1.5x (2560x1440 logical). See
CLAUDE.md, "Running headless", for why the order matters.

    python3 build/tools/mkedid.py 4k > /tmp/edid.bin
    CARD=card2; CONN=HDMI-A-1     # confirm nothing is plugged into it
    C=/sys/kernel/debug/dri/$(basename $(readlink -f /sys/class/drm/$CARD/device))/$CONN
    echo detect | sudo tee /sys/class/drm/$CARD-$CONN/status   # force a re-probe
    sudo dd if=/tmp/edid.bin of=$C/edid_override bs=128 count=1
    echo on | sudo tee /sys/class/drm/$CARD-$CONN/status
    sudo systemctl restart gdm

Confirm in `/tmp/starling-session-1001.log`:

    [DrmView] Created: 3840x2160, engine running
    [DisplayLayout] scale 1.5 for 3840x2160 ... logical 2560x1440

Put it back when the demo is over: `echo detect | sudo tee
/sys/class/drm/$CARD-$CONN/status`.

**Trap.** A connector that is already forced on caches its mode list. Writing a
new EDID over it changes nothing until you cycle through `detect` — which is why
the `detect` line comes first. Swapping 1080p for 4K silently appears to fail
without it.

## 2. Give the session user Claude Code

`claude` lives under your login user's home, which is `drwxr-x---`, so
`starling` cannot even traverse to it. Install the binary and the credential:

    sudo install -d -o starling -g starling -m 755 \
        /home/starling/.local/bin /home/starling/.local/share/claude/versions
    sudo cp ~/.local/share/claude/versions/<VER> \
        /home/starling/.local/share/claude/versions/<VER>
    sudo ln -sf /home/starling/.local/share/claude/versions/<VER> \
        /home/starling/.local/bin/claude
    sudo install -d -o starling -g starling -m 700 /home/starling/.claude
    sudo cp ~/.claude/.credentials.json /home/starling/.claude/.credentials.json
    sudo chown -R starling:starling /home/starling/.local /home/starling/.claude
    sudo chmod 600 /home/starling/.claude/.credentials.json

Copy **only** the credential — not `~/.claude/projects/`, which is hundreds of
MB of your own transcripts.

Skip first-run onboarding by writing a minimal `/home/starling/.claude.json`
(mode 600, owned by starling). Without `hasCompletedOnboarding` the CLI runs the
OAuth login flow even though a valid credential is present:

    {
      "hasCompletedOnboarding": true,
      "installMethod": "native",
      "autoUpdates": false,
      "oauthAccount": { ...copied from yours... }
    }

**Trap — the shared credential rotates.** Both accounts using one OAuth refresh
token means every refresh in *your* session invalidates the copy, and the CLI
says "Login expired". Re-copy `.credentials.json` immediately before the demo,
or better: run `/login` once in the workspace terminal so it holds its own, or
set `ANTHROPIC_API_KEY`, which does not rotate.

**Install the app-launching skill**, or every "open it in Chrome" has to spell
out the command:

    sudo install -d -o starling -g starling -m 755 \
        /home/starling/.claude/skills/starling-apps
    sudo install -o starling -g starling -m 644 \
        .claude/skills/starling-apps/SKILL.md \
        /home/starling/.claude/skills/starling-apps/SKILL.md

It teaches Claude Code the things it cannot guess from a shell prompt: that
host apps start with `app-run`, that a foreground `app-run` wedges its own
session, that first-party apps cannot be launched from a terminal at all, and
that the window lands in whichever workspace is active. With it in place the
demo's launch steps are plain English and the agent produces the right command
itself. Confirm with `claude -p "list your skills"` as `starling` — the answer
should include `starling-apps`.

## 3. Scrub identity before recording

The welcome box shows the account name. Patch it in
`/home/starling/.claude.json`:

    "oauthAccount": { "displayName": "Starling Demo", ... }

That field is not refreshed, so it sticks. Everything else is harder:

- **`/status` cannot be scrubbed.** It shows the real Organization and Email,
  fetched live from the API — editing the local file does not help, and neither
  does `chattr +i` (tested, both fail). **Do not open `/status` on camera.**
- **`/mcp`** lists your claude.ai connectors (Gmail, Calendar, Drive). Skip it.
- **Task Manager leaks your username** — it lists `sshd-session: <you>@notty`
  along with everything else running on the box.
- **Chrome's profile avatar** is one click from your Google account. Launch with
  a throwaway `--user-data-dir` if that matters.
- **VS Code** shows a GitHub "Sign In" button but is signed out by default.

For a genuinely clean recording, use a separate demo account rather than
scrubbing.

## 4. Driving it

`build/shell-drive.py` takes **one action per argv element**, and coordinates are
**logical** px (2560x1440 at 4K/1.5x), not physical:

    sudo build/shell-drive.py "move 1280 700" "key ctrl+down" "sleep 2" \
        "shot /tmp/ws.png"

**Trap.** Click button *centres*, not edges. Clicking the `+`'s left edge misses
it, the launcher never opens, and every subsequent `type` lands in the terminal
as a shell command — which looks like the app failed rather than the click.

**Trap.** Never send blind key sequences at the CLI's onboarding prompts.
Screenshot between each one. A wrong `down`+`enter` picks "No, exit"; the next
`up` then recalls the command from bash history and re-runs it, and the terminal
ends up garbled. `reset` clears it.

## 5. Recording it

**There are two recording paths and only one belongs on camera.**

| | `shell-drive record-start` | **Ctrl+Shift+R** |
| --- | --- | --- |
| For | test evidence | the product feature |
| Resolution | 960x540 (hardcoded 4x downscale) | full panel (3840x2160) |
| Encoder | libx264 over a raw frame dump | VAAPI, hardware |
| Output | the path you pass | `~/Videos/Screen Recording <date>.mp4` |

The tooling path downscales to keep raw dumps small for the test suite. It is
not a demo recorder. **Use Ctrl+Shift+R**, which is the same recorder a user
gets; it toggles start/stop and writes to `~/Videos`.

Before you record:

- **Turn the screensaver off** — Settings > Screensaver > Never. The default
  idle is 600s (10 minutes, like macOS), which a talk-through with pauses will
  reach. When it fires you get a dimmed desktop with a clock, and the clicks
  that dismiss it look like failed interactions. The picker writes one line to
  `~/.config/starling/screensaver` (`0` disables), read **at mount**, so a
  scripted setup can drop the file in before starting the session instead of
  clicking through Settings — but a file written to a session already running
  does nothing. `STARLING_SCREENSAVER_IDLE` overrides it without touching the
  user's config.
- **Expect the recording indicator**: a red dot with elapsed time in the menu
  bar, top right. It is in the capture and cannot be hidden.
- **Close and relaunch anything already running.** A VS Code window that had
  been through a pane resize crashed mid-capture with "The window terminated
  unexpectedly (reason: 'clean-exit', code: '0')".

After you record:

- **The file is VFR**, not constant-rate — capture is damage-driven, so an idle
  desktop presents few frames (a 15.5s clip came out as 107 frames with
  timestamps at 0.000, 0.038, 0.206, 0.222, 0.490 …). Players that honour PTS
  are fine; some editors and upload pipelines are not and will play it fast.
  Normalise before editing:

      ffmpeg -i "Screen Recording ....mp4" -vsync cfr -r 30 demo.mp4

## 6. Zooming in

A 4K desktop delivered at 1080p is unreadable — a terminal prompt is ~7px tall
after the downscale. **Record at 4K and zoom in the edit.** The capture has 2x
of zoom in hand: a 1:1 crop is pixel-native, so a zoomed shot is *sharper* than
the unzoomed frame, not softer. Nothing is upscaled and nothing is lost.

    build/tools/zoom-edit.sh IN.mp4 OUT.mp4 driver 2 1.5   # ease to the driver
    build/tools/zoom-edit.sh IN.mp4 OUT.mp4 tabs   1 1     # ease to Chrome/Blender

Presets are `driver` (rail + middle column), `tabs` (the right-hand pane) and
`full`. Cut between per-shot renders in your editor.

**The `fps` filter before `zoompan` is load-bearing.** The recorder writes VFR
and `zoompan` counts frames, not seconds, so without normalising first an 8s
span of a mostly-idle desktop collapsed to 1.8s of output — 54 frames instead
of 240. Same trap as the VFR note in §5, in a place where it silently produces
a plausible-looking file.

### Or zoom live, while recording

**Ctrl+Shift+=** zooms the recording in, **Ctrl+Shift+-** zooms out — 1x, 1.5x,
2x, 3x, eased over ~0.3s, centred on the pointer. Only while recording; it is a
no-op otherwise.

**Nothing on screen moves.** This crops what the encoder sees, not the desktop,
so the audience in the room sees nothing and the take comes out zoomed. On a 4K
panel the 2x step is the 1:1 crop, so a zoomed shot is *sharper* than the wide
one, exactly as in the edit-time route above — and there is no edit step.

Because the screen does not move, the **menu-bar indicator is the only feedback**:
it reads `0:07  2.0×` while zoomed. Watch it, or you are narrating blind.

That applies to tooling as well, and it is easy to forget: `shell-drive.py shot`
captures the **panel**, not the crop, so a screenshot taken mid-take always
looks unzoomed and tells you nothing about framing. Driving this from a script
means computing the frame instead of looking at it — pointer position, then step
count — and checking the result against the indicator, or against a frame pulled
out of the finished file with `ffmpeg -ss`.

**Centre the driver zoom on the content, not on the column.** A fresh terminal
draws from the top, so pointing at the middle of the driver pane — the obvious
place — frames blank space below the text. At 2x on a 4K panel the crop is
1080 physical px tall, and the Claude Code welcome box, the setup commands and
the prompt as it is typed all sit above it; the input line sits below it. Both
ends of the interesting part are outside the shot, and nothing warns you,
because the screenshots look perfect. In one take this cost two beats in each
workspace — the agent starting, and the prompt going in — which were empty
frames until about two screens of output had scrolled down into the crop. Put
the pointer near the **top** of the driver column while a terminal is still
mostly empty, and move it down as the transcript fills.

Re-taking the centre on every press means the zoom follows the pointer — point
at the driver, press twice, point at Chrome, press again, and it travels. Zoom
resets to 1x when a recording stops, so a take never inherits the last one's
crop. Window recordings do not offer it: they already drive `set_crop`
themselves to track the window, and a second meaning for the same call would
fight it.

**At 3x, another Ctrl+Shift+= is a pan, not a zoom.** The step index clamps at
the top of the ladder but the centre is re-taken regardless, so pressing `=`
again at 3x holds 3x and simply glides to wherever the pointer now is. That is
the whole technique for following a terminal: park at 3x and re-press as the
work moves down the column. Panning at 2x is uglier — you have to go `-` then
`=`, which dips to 1.5x and back — so if a beat needs to travel, do it at 3x.

**What each step actually covers**, on the 4K panel at 1.5x scale (2560x1440
logical). Aim with these rather than by eye, because you cannot see the crop:

| Zoom | Crop, logical px | Good for |
| --- | --- | --- |
| 1x | 2560 x 1440 | the whole layout, and the full-screen launcher |
| 1.5x | 1707 x 960 | one whole pane of the three-column layout |
| 2x | 1280 x 720 | a browser page, an editor buffer — and 1:1 native |
| 3x | 853 x 480 | the rail, a single button, terminal text |

The driver column is only ~667 logical px wide, so 3x is what makes it fill the
frame; the tab column is ~1580 wide, so 1.5x–2x suits it. Nothing above 1.5x
covers a column's full height (1360), which is why panning exists.

**The launcher swallows the zoom keys.** While it is open the shell's hook
never sees Ctrl+Shift+± — press it three times and the indicator still reads
3.0×. So "zoom in on the add button, click it, then zoom out to reveal the
launcher" cannot be done in that order. Pull the camera back *before* the
click: push in on the button, hold, pull out, then click. On screen it reads
identically, and it is the only order that works.

---

## The shape of the demo

Start on the **normal desktop** — wallpaper, dock, menu bar — so there is a
before. Then `Ctrl+Down` into workspace mode and build two workspaces:

1. **Web** — Claude Code writes a landing page, then opens Chrome and VS Code
   on it *as separate instructions*, then edits the page while both are open
   and both update on their own.
2. **Blender** — Claude Code models a bird, opens Blender, then restyles the
   model and Blender reloads it.

The payoff in both is the same: the driver column and the tab column are on
screen **at the same time**, so the agent's diff and the result are in one
frame. Nothing is cut away to a different window.

**Split the asks up.** It is tempting to have one prompt write the page, serve
it and launch both apps — it works, and it wastes the demo. Each app opening
is a transition worth its own beat: ask, pull the camera out as the tab lands,
push in on what it rendered. One prompt collapses all of that into a single
jump cut. Tell the first prompt *not* to open anything ("Do not open any other
app yet"), then ask for Chrome, then ask for VS Code.

### Let the camera lead

The zoom is not decoration on top of the demo, it is how the demo is narrated,
and it has one rule: **push in on a thing before acting on it, pull out to show
what the action did.** In on the rail, then rename. In on the add button, out,
then click — the launcher fills the frame it left. In on the driver, then type.
Out as a tab arrives, in on what the tab is showing. A viewer who never sees
the pointer still knows where to look, because the frame already moved there.

### The three live-update mechanisms are NOT the same

This is the part to get right, because only one is automatic for free:

| Target | How it updates | Automatic? |
| --- | --- | --- |
| **Chrome** | a dev-only poll-and-reload script inside the page | **yes**, ~500ms |
| **VS Code** | reloads an unmodified buffer when the file changes | **yes** |
| **Blender** | `File > Revert` — it does not watch the .blend | **no**, 3 clicks |

Ask for the reload script explicitly when the page is written; retrofitting it
means an edit that itself needs a reload to take effect.

---

## Demo A — the Web workspace

Camera moves are in **bold**; everything else is an ordinary click or keystroke.
Zoom steps are counted from wherever you are — `=` ×3 means three presses of
Ctrl+Shift+=, which is 1x to 3x.

1. **Start on the empty workspace.** `Ctrl+Down` before you roll, so the take
   opens on workspace mode with nothing in it. Let it sit ~5s wide.
2. **Point at the rail and `=` ×3.** The rail is a twentieth of a 4K frame; at
   3x the rows and the menu are large enough to read.
3. Now, inside that frame: `+ New` > right-click the new row > Rename > type
   `Web` > Enter. The first keystroke replaces the old name.
4. **`-` ×3 back to wide**, so the named workspace is seen in context.
5. **Point at the middle column's `+` and `=` ×3.** Hold on "Choose an app to
   work in" for a beat — this is the thing about to be clicked.
6. **`-` ×3 back to wide, *then* click the `+`.** Not the other way round: the
   launcher eats the zoom keys once it is up (see §6). The launcher arrives
   full-frame at 1x, which is the only way it fits.
7. Click **Terminal**. It appears in the driver column, still wide.
8. **Point near the *top* of the driver column and `=` ×3** — a fresh terminal
   draws from the top, so aim there, not at the middle of the pane. Then:

       mkdir -p ~/landing && cd ~/landing
       export PATH=$HOME/.local/bin:$PATH
       claude --dangerously-skip-permissions

   The welcome box draws inside the frame you just set.

9. **Pan down to the prompt line: point at the bottom of the driver column and
   press `=` once more.** At 3x that re-centres without changing zoom. Now type
   the build prompt — it appears in the input box under the camera, which is
   the point. Note the two asks: the live-reload script, and *no* app launches
   yet.

   > Build a landing page for Starling, a macOS-style Linux desktop environment
   > written in Swift on the Flutter engine. Write index.html here: dark theme,
   > hero with the name and a one-line pitch, three feature cards (Wayland
   > compositor, first-party apps, workspace mode), download call to action,
   > inline CSS, no external assets. At the end of the body add a small dev-only
   > live-reload script that polls this page with fetch HEAD every 500ms and
   > reloads when the Last-Modified header changes. Then serve this directory on
   > port 8321 in the background with `python3 -m http.server` and curl it to
   > confirm. Do not open any other app yet.

10. **Follow the answer with two more `=` presses**: back up to the top as the
    reply starts (a short transcript sits at the top of the pane), then down
    again as it fills. Takes about a minute.

11. **Pan to the prompt line** and ask for the browser — plain English, because
    the `starling-apps` skill from §2 supplies the mechanics:

    > Now open the page in Chrome.

    Without the skill you have to dictate it —
    `` `app-run chrome http://localhost:8321/` in the background `` — and a
    foreground `app-run` blocks the agent's session until you close the app.

12. **`-` ×3 as Chrome lands.** The tab arriving is the transition; give it a
    couple of seconds wide, driver and browser in one frame.
13. **Point at the page and `=` ×2.** 2x is the 1:1 crop on a 4K panel, so the
    hero is pixel-native — sharper than the wide shot, not softer. Hold, then
    **`-` ×2**.
14. **Back to the driver, `=` ×3**, and do it again for the editor:

    > Now open that file in VS Code.

    **`-` ×3** as it lands, **`=` ×2** on the buffer.

15. **The live edit.** Select the Chrome tab again, click into the driver —
    Chrome stays rendered in the tab column beside it — and ask for something
    unmistakable:

    > Change the accent colour throughout the page from blue to warm amber, and
    > change the hero headline gradient to match. Keep everything else the same.

    Type it at 3x on the driver, then **`-` ×3 to wide before the edit lands** —
    the whole point is that the diff is still printing on the left when the
    browser on the right reloads itself, and only the wide frame holds both.
    Claude says so too: *"the server picked up the new mtime, so the open Chrome
    tab reloaded itself."*

16. **Flip back to the VS Code tab** and **`=` ×2** — the buffer already shows
    the new `--accent`, with the colour swatch in the gutter. Nothing was
    reloaded by hand.

Run end to end with the camera work above, that is about twelve minutes of
tape, most of it the agent thinking. Cut the waits out afterwards and it lands
near five.

## Demo B — the Blender workspace

Same camera grammar as Demo A — in on the rail to name it, in on the add button
before clicking, out for the launcher, 3x on the driver and pan as it fills, out
when the tab lands, in on the result. Only the differences are spelled out here.

1. **`+ New`** in the rail, rename it `Blender`. Note that "Remove Workspace"
   goes from disabled to enabled once a second workspace exists.
2. **Driver**: Terminal > `~/model` > `claude`, same as before.
3. Build it:

   > Create a 3D model for Blender. Write model.py using bpy that builds a
   > low-poly bird from primitives - body, head, beak, tail and two wings - each
   > with a coloured material, plus a camera and a three-point light setup aimed
   > at it. Run it headless with `blender --background --python model.py` to save
   > starling.blend here. Then launch this in the background so your session
   > stays free: `app-run blender /home/starling/model/starling.blend`

   **Budget 4-6 minutes.** It renders preview stills and iterates — on one run
   it found the wings were sitting inside the body's half-width and therefore
   invisible, and moved them outboard; on another it caught two local-axis
   scaling mistakes the same way. That self-correction is the best part of the
   demo, so let it run rather than cutting away; but do not expect it to be
   quick, and say so if you are narrating live.

   **Trap — `pgrep -x blender` does not mean Blender opened.** Rendering those
   preview stills *is* a `blender` process, so anything waiting on the app to
   appear fires a minute or two early. It cost a zoom pull-back onto an empty
   tab column. Match on the GUI invocation instead:

       pgrep -a -x blender | grep -v -- --background

   When the window finally lands, **press Home over the viewport** — the saved
   view leaves the bird a speck among the camera and light gizmos, and Home
   (View All) frames it. Then **`=` ×3 on the model**: it is a small object in a
   big pane, and 3x is the only step that fills the frame with it. Nothing else
   in the demo needs 3x on the tab column.

4. **The live edit**, with Blender already open:

   > Make the body bright crimson red and the wings gold, and make the wings
   > noticeably larger. Re-run model.py headless to regenerate starling.blend in
   > place. Do not relaunch Blender - it is already open.

5. **Reload it by hand**: `File > Revert`, then confirm "Revert to the Saved
   File" in the dialog. The new model appears. Blender has no file watcher, so
   there is no way around this — plan the narration for it ("Blender does not
   watch the file, so we reload it") rather than being surprised on camera.

## Reset between runs

    sudo pkill -x chrome; sudo pkill -x blender; sudo pkill -x code
    sudo pkill -u 1001 -x claude
    PID=$(sudo ss -lptn 'sport = :8321' | grep -oE 'pid=[0-9]+' | cut -d= -f2 | head -1)
    [ -n "$PID" ] && sudo kill "$PID"
    sudo rm -rf /home/starling/landing /home/starling/model

**Trap.** Apps launched in the CLI's foreground shell are its children — killing
`claude` kills Chrome and Blender with it. Background them (`ctrl+b`) if you want
them to outlive the session.

To revert the display: `echo detect | sudo tee /sys/class/drm/card1-HDMI-A-1/status`.

To remove the copied credentials entirely:

    sudo rm -rf /home/starling/.claude /home/starling/.claude.json \
                /home/starling/.local/share/claude /home/starling/.local/bin/claude

The token stays valid in that account until you do.

## Known rough edges, so they do not surprise you on camera

- **Capture-on-open follows the *active* workspace**, so a slow-starting app can
  land in whichever workspace you switched to while it was launching. VS Code did
  exactly this — launched in workspace 1, surfaced in workspace 2.
- **The launcher searches display names**, not app ids: `appstore` and
  `taskmanager` match nothing, `App Store` and `Task Manager` do. A miss leaves
  the launcher open and the next keystrokes go to the focused app.
- **A workspace can only live on one output** — the panes resize the real
  clients, and one client has one buffer size.
