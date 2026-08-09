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
- Chrome, VS Code and Blender reachable. Chrome/VS Code have install records;
  **Blender does not** — its binary is at `/usr/bin/blender` and `app-run`
  finds it anyway, but it will not appear in the launcher or dock. Add a record
  with `app-install --record blender` if you want it discoverable.
- `sudo` on the box (shell-drive needs `/dev/uinput` and signals the shell).

## 1. Give it a display

The dev box is usually headless. See CLAUDE.md, "Running headless", for why the
order matters. 4K is worth it: more room for the three columns, and it exercises
the fractional-scale path at 1.5x (2560x1440 logical).

    python3 build/tools/mkedid.py 4k > /tmp/edid.bin
    C=/sys/kernel/debug/dri/0000:c6:00.0/HDMI-A-1
    echo detect | sudo tee /sys/class/drm/card1-HDMI-A-1/status   # force a re-probe
    sudo dd if=/tmp/edid.bin of=$C/edid_override bs=128 count=1
    echo on | sudo tee /sys/class/drm/card1-HDMI-A-1/status
    sudo systemctl restart gdm

Confirm in `/tmp/starling-session-1001.log`:

    [DrmView] Created: 3840x2160, engine running
    [DisplayLayout] scale 1.5 for 3840x2160 ... logical 2560x1440

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
  that dismiss it look like failed interactions.
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

Re-taking the centre on every press means the zoom follows the pointer — point
at the driver, press twice, point at Chrome, press again, and it travels. Zoom
resets to 1x when a recording stops, so a take never inherits the last one's
crop. Window recordings do not offer it: they already drive `set_crop`
themselves to track the window, and a second meaning for the same call would
fight it.

---

## The shape of the demo

Start on the **normal desktop** — wallpaper, dock, menu bar — so there is a
before. Then `Ctrl+Down` into workspace mode and build two workspaces:

1. **Web** — Claude Code writes a landing page, opens Chrome and VS Code, then
   *edits the page while both are open* and both update on their own.
2. **Blender** — Claude Code models a bird, opens Blender, then restyles the
   model and Blender reloads it.

The payoff in both is the same: the driver column and the tab column are on
screen **at the same time**, so the agent's diff and the result are in one
frame. Nothing is cut away to a different window.

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

1. **Start on the desktop.** Let it sit for a beat before `Ctrl+Down`.
2. **Name the workspace**: right-click the rail row > Rename > `Web` > Enter.
   The first keystroke replaces the old name.
3. **Driver**: the middle column's `+` > `Terminal`. Then:

       mkdir -p ~/landing && cd ~/landing
       export PATH=$HOME/.local/bin:$PATH
       claude --dangerously-skip-permissions

4. **One prompt builds and opens everything.** Note the two specific asks — the
   live-reload script, and *background* launches so the agent's session stays
   free (a foreground `app-run` blocks it until you close the app):

   > Build a landing page for Starling, a macOS-style Linux desktop environment
   > written in Swift on the Flutter engine. 1) Write index.html here: dark
   > theme, hero with the name and a one-line pitch, three feature cards
   > (Wayland compositor, first-party apps, workspace mode), download call to
   > action, inline CSS, no external assets. At the end of the body add a small
   > dev-only live-reload script that polls this page with fetch HEAD every
   > 500ms and reloads when the Last-Modified header changes. 2) Serve this
   > directory on port 8321 in the background with `python3 -m http.server` and
   > curl it to confirm. 3) Launch both of these in the background so your
   > session stays free: `app-run chrome http://localhost:8321/` and
   > `app-run vscode /home/starling/landing/index.html`

   Both arrive as tabs. Chrome is the one to leave selected.

5. **The live edit.** Click into the driver — Chrome stays rendered in the tab
   column beside it — and ask for something unmistakable:

   > Change the accent colour throughout the page from blue to warm amber, and
   > change the hero headline gradient to match. Keep everything else the same.

   By the time the diff finishes printing, Chrome has already reloaded itself.
   Claude says so too: *"the server picked up the new mtime, so the open Chrome
   tab reloaded itself."*

6. **Then flip to the VS Code tab** — the buffer already shows the new
   `--accent`, with the colour swatch in the gutter. Nothing was reloaded by
   hand.

## Demo B — the Blender workspace

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
   invisible, and moved them outboard. That self-correction is the best part of
   the demo, so let it run rather than cutting away; but do not expect it to be
   quick, and say so if you are narrating live.

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
