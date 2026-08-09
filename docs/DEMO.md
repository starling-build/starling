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

---

## Demo A — landing page (workspace 1)

1. **Enter workspace mode**: `key ctrl+down` (or desktop context menu).
2. **Driver**: click the middle column's `+`, type `Terminal`, Enter.
3. In the terminal:

       mkdir -p ~/landing && cd ~/landing
       export PATH=$HOME/.local/bin:$PATH
       claude --dangerously-skip-permissions

   **Trap.** A shell opened before `~/.local/bin` existed will not have it on
   PATH — hence the explicit `export`, or use the absolute path.

   **Trap.** `--dangerously-skip-permissions` is what lets it run the server and
   launch a browser unattended. Only reasonable on a disposable box. Answer the
   trust prompt (Enter) and the bypass warning (`down`, Enter) one at a time.

4. **One prompt does all three steps** — the point is that the agent works, not
   that you do:

   > Do three things. 1) Write index.html here: a self-contained dark-theme
   > landing page for Starling, a macOS-style Linux desktop environment written
   > in Swift on the Flutter engine. Hero with the name and a one-line pitch,
   > three feature cards (Wayland compositor, first-party apps, workspace mode),
   > and a download call to action. Inline CSS, no external assets or fonts.
   > 2) Serve this directory on port 8321 in the background with
   > `python3 -m http.server`, and curl it to confirm it returns the page.
   > 3) Open it for review by running: `app-run chrome http://localhost:8321/`

   **Trap — port 8080 is taken** on this box by qBittorrent's WebUI. The server
   fails to bind and `curl` cheerfully returns qBittorrent's login page. Use
   8321.

5. **Chrome appears as a tab.** This is the load-bearing bit: workspace mode
   *refuses* to launch non-first-party apps from its own launcher, but a Wayland
   client **spawned by the driver** is captured automatically.

6. Optional — open the file in an editor from the same session:

   > Also open the page in VS Code by running:
   > `app-run vscode /home/starling/landing/index.html`

   VS Code's first run shows a Copilot sign-in modal and a theme wizard. Dismiss
   both before recording; they do not come back.

## Demo B — Blender model (workspace 2)

1. **`+ New`** in the rail. The new workspace starts empty; the first keeps its
   windows and its driver.
2. **Driver**: Terminal again, then `~/model`, then `claude`.
3. Prompt:

   > Create a 3D model for Blender. Write model.py using bpy that builds a
   > low-poly bird from primitives - body, head, beak, tail and two wings -
   > gives each a coloured material, and adds a camera plus a three-point light
   > setup aimed at it. Then run it headless with
   > `blender --background --python model.py` to save starling.blend in this
   > directory, and confirm the file exists and its size.

   It writes the script, runs Blender headless, then test-renders with EEVEE to
   check the result actually reads as a bird — the first pass put the camera
   behind it with the beak hidden, and it repositioned the camera and lights and
   trimmed the tail on its own. That self-correction is the good part of the
   demo; give it time rather than cutting away.

4. Open it:

   > Now open it for review by running:
   > `app-run blender /home/starling/model/starling.blend`

5. Blender's first run shows a Quick Setup dialog, then a splash. Dismiss both,
   then **press `home`** in the viewport to frame the model — it is small and
   off-centre from the default view, and looks like an empty scene until you do.

---

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
