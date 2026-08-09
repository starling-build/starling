---
name: starling-apps
description: Open and launch apps on the Starling desktop from a terminal — Chrome, VS Code, Blender and other host apps, plus URLs and files. Use whenever the user asks to open, launch, show, preview or pull up something in an app.
---

# Opening apps on the Starling desktop

You are running in a terminal **inside** the Starling desktop, and the user is
looking at the same screen. "Open it in Chrome" means start Chrome here, now —
not print a URL and stop.

## One command

    app-run <app> [args…] &

That is the whole interface for host apps. `app-run` builds the environment
they need — the compositor's Wayland socket, the GPU, the display scale, a
private per-app home, and the registry-aware `xdg-open` shim on their PATH.
Starting the vendor binary yourself gets a broken window or none at all.

    app-run chrome http://localhost:8321/ &
    app-run vscode /home/starling/landing/index.html &
    app-run blender /home/starling/model/starling.blend &

Known ids: `chrome`, `vscode`, `blender`, `gimp`, `slack`, `telegram`, `zoom`,
`teams`, `discord`, `spotify`. Run `app-run` with a name it does not know and
it prints the current list. For something with no id of its own:
`app-run <name> -- <cmd> [args…]` runs any command inside the app runtime.

## Rules

1. **Always background it.** A foreground `app-run` does not return until the
   app exits, which wedges this session — you cannot answer, and the user
   cannot tell the difference between "thinking" and "stuck". A trailing `&`
   is enough.
2. **No sudo.** You are already the session user.
3. **Do not relaunch what is open.** Check `pgrep -x chrome` first. If the app
   is up and only the content changed, say so rather than opening a second
   window — a served page with a reload script has probably updated itself
   already.
4. **Serve it, don't `file://` it,** when the page should keep up with edits:
   `python3 -m http.server <port>` in the background, plus a small poll-and-
   reload script in the page, beats asking the user to press refresh.
5. **`xdg-open` here is the host's, not Starling's.** The registry-aware shim
   is only on the PATH of apps launched *through* `app-run`; in this terminal
   `xdg-open` resolves to `/usr/bin/xdg-open`. Name the app explicitly instead.
6. **Say what you opened and where.** The user may be looking at a different
   workspace than the one it landed in.

## First-party apps cannot be launched from here

Terminal, Files, Settings, Text Editor, Calculator, Task Manager, Image Viewer,
Video Player and App Store are children of the shell: they hand their frames
back over a pipe the shell owns. Started from a shell there is no such pipe, so
the binary exits immediately — status 0, no output, no window, nothing to
debug. If the user wants one of those, tell them it has to come from the
launcher (the `+` in a workspace pane, or the dock).

## Where the window lands

In workspace mode the new window is captured as a **tab in whichever workspace
is active at the moment it maps**. A slow-starting app can therefore surface in
a different workspace than the one it was asked for, if the user switches while
it loads. In normal mode it is an ordinary floating window.

## Showing a page vs. driving one

`app-run chrome …` is for when a human is going to look at it.

When you need to *operate* a page instead — read it back, fill a field, click
something — use `agent-client` (`launch`, `goto`, `fill`, `click`, `text`,
`shot`), which addresses pages by CSS selector over the DevTools protocol.
Those windows are owned by the agent and are not the same as putting a browser
in front of the user.
