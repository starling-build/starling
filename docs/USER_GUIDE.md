# Starling User Guide

A tour of the desktop: what you see at first login, how to move around, the
keyboard shortcuts, the apps, and how to install more. If Starling is not yet
installed, start with the [Installation Guide](INSTALL.md).

Starling's interaction model is close to macOS — if you have used a Mac, most
of this will feel familiar.

---

## Choosing Starling at login

Installing Starling doesn't replace your current desktop — it adds a session
you pick at the login screen. To start it:

1. **Click your name** at the login screen.
2. **Open the session menu** — usually a gear, or a small icon in a lower
   corner of the password box.
3. Choose **Starling** from the list, then enter your password and sign in.

Starling stays selected for next time. The session menu only appears with a
Wayland-capable login manager (GDM has one); it looks a little different on
LightDM or SDDM, but the step is the same — find the session picker and choose
Starling. (See the [Installation Guide](INSTALL.md#log-in-to-starling) if you
don't see a session menu at all.)

## First login

Once you sign in, you land on the desktop:

- a **wallpaper** filling the screen,
- a thin **menu bar** across the top, with the clock and status indicators,
- a **dock** floating at the bottom, holding your apps.

That is the whole desktop. Everything else is reached from the dock, the
Launchpad, or a right-click on the wallpaper.

---

## The dock

The dock sits at the bottom of the screen. Out of the box it holds the
first-party apps, in order: **Launchpad**, **Settings**, **Files**,
**Terminal**, **Text Editor**, **Calculator**, **App Store**, **Video
Player**.

- **Click** an icon to launch or focus that app.
- A **running app shows an indicator** under its icon.
- **Drag** an icon to reorder the dock.
- **Right-click** an icon for its menu, including **Remove from Dock**.

Installed apps that aren't pinned appear in the dock while they run, and drop
off when they close.

---

## The Launchpad

The first dock icon opens the **Launchpad** — a full-screen grid of every app
Starling knows about, over a blurred background.

- **Click** any app to launch it.
- **Type** to filter the grid by name — start typing and only matching apps
  remain.
- Click empty space or press **Esc** to dismiss it.

---

## The menu bar

The bar along the top carries the clock and date on the left, and on the right
the Wi-Fi and battery indicators, a **bell**, and the **control centre**.

Click the control-centre icon for a panel of quick toggles:

- **Wi-Fi** — join a network without opening Settings.
- **Dark Mode** — switches the whole desktop and every first-party app.
- **Tiling** — retiles the current space; toggle it off to restore floating
  windows.
- **Muted** — mute or unmute output, with **volume** and **brightness**
  sliders below the tiles.
- **Record** and **Record App** — see
  [Recording the screen](#recording-the-screen).

The **bell** collects notifications instead of interrupting you with banners:
nothing steals focus, and you read what happened when you choose to. Click it
for the list, **Esc** to dismiss.

---

## Recording the screen

Starling records itself, with no extra software.

- **Record** (control centre, or **Ctrl + Shift + R**) captures the whole
  screen.
- **Record App** opens Mission Control and asks which window you want. It
  captures that window's own content, not the region of screen it sits in, so
  windows stacked on top never appear and moving or resizing the window
  mid-recording doesn't spoil the take. The pointer is drawn in and follows
  the window.

While a recording runs, a **red dot and a running clock** sit in the menu
bar, so a recording can never be going unnoticed. Stop it the same way you
started it.

Recordings land in **`~/Videos`** as MP4, and the Video Player opens them.
Where the machine has a hardware H.264 encoder, the frame the compositor
already drew goes straight to it as a dma-buf and the CPU never touches a
pixel — on a modern laptop that costs about 0.05 of a core. Machines without
one fall back to a software encoder, which works but costs more.

---

## The screensaver

Leave the desk for ten minutes and the desktop dissolves into a screensaver:
your own screen, blurred and drifting behind a slow liquid warp, with the
time and date floating over it. Any key, click, or mouse movement brings it
straight back — nothing is asked for, so it is decoration, not a lock.
**Ctrl + Shift + S** shows it immediately.

Change the idle time (or turn it off) in **Settings → Appearance →
Screensaver**. Video playback holds it off: an app that tells the desktop
it is playing something — Chrome, Firefox, a video player — keeps the
screensaver away for as long as it says so, so a film watched without
touching the mouse is never interrupted.

For **aerial footage** in place of the warp, drop a video file in
`~/.local/share/starling/aerials/`; the screensaver dissolves into it and
loops it. Starling ships none of its own — the warp needs no assets, and the
clips worth watching are large. Any shape works: letterbox bars are cropped
away and the picture fills the screen.

---

## Windows

Windows have a title bar with three **macOS-style colored circle buttons** on
the left — close, minimize, maximize.

- **Drag the title bar** to move a window.
- **Drag an edge or corner** to resize it.
- **Double-click the title bar** to toggle maximized.
- The **maximize** button does the same.

By default windows **float** — you place them freely. You can switch the whole
desktop to **tiling** (a dwm-style master-and-stack layout, where windows share
the screen automatically) with the **Tiling** tile in the
[control centre](#the-menu-bar), or the **Tiling Windows** switch in
[Settings](#settings). Toggling it back restores your floating layout.

---

## Spaces and Mission Control

Starling has **spaces** (virtual desktops) and a **Mission Control** overview,
driven from the keyboard the way macOS does it.

| Do this | To |
|---|---|
| **Ctrl + →** / **Ctrl + ←** | Slide to the next / previous space |
| **Ctrl + Shift + →** / **←** | Carry the focused window to the next / previous space |
| **Ctrl + Tab** | Cycle through your spaces |
| **Ctrl + ↑** | Open **Mission Control** (all spaces and windows at once) |
| **Ctrl + ↓** | Open your **workspace** (see below) |
| **Esc** | Close Mission Control |

In Mission Control, **Ctrl + ← / →** retargets the active space instantly. To
add a space, right-click the wallpaper and choose **New Desktop**.

`Ctrl` + arrows belong to the system — apps never see them — so they work no
matter which window is focused.

---

## Right-click the desktop

Right-click anywhere on the wallpaper for the desktop menu:

- **Change Wallpaper**
- **Mission Control**
- **New Desktop** — add a space
- **Workspace**
- switch **appearance** (light / dark)
- **Remove This Desktop** — when you have more than one

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| **Ctrl + →** / **←** | Adjacent space |
| **Ctrl + Shift + →** / **←** | Move focused window to adjacent space |
| **Ctrl + Tab** | Cycle spaces |
| **Ctrl + ↑** | Mission Control |
| **Ctrl + ↓** | Workspace mode |
| **Ctrl + Shift + R** | Start / stop screen recording |
| **Ctrl + Shift + S** | Show the screensaver now |
| **Ctrl + Space** | Toggle the input method (fcitx5, for CJK and other IME input) |
| **Esc** | Close Mission Control; release a taken-over agent window |
| Double-click title bar | Maximize / restore a window |

---

## The apps

Nine first-party apps ship with Starling, all written against its Swift
framework:

- **Settings** — appearance, displays, network, sound, and system information.
  See [below](#settings).
- **Files** — browse your home directory and the filesystem.
- **Terminal** — a real terminal with a PTY; runs your login shell (`$SHELL`,
  falling back to bash). TUI programs like `vim` and `htop` work.
- **Text Editor** — a plain-text editor.
- **Calculator** — a basic calculator.
- **App Store** — install more applications. See
  [below](#installing-more-apps).
- **Task Manager** — CPU, memory, disk and network with live sparklines, a
  sortable process table, and End Process.
- **Video Player** — plays your recordings and other video. For Starling's own
  recordings it decodes on the GPU and never copies a frame through the CPU.
- **Image Viewer** — opens images from Files.

---

## Settings

The Settings app has nine sections in its sidebar:

- **General** — **System Information**: the Starling version, your Ubuntu
  release, kernel, and Mesa version.
- **Network** — see and join **Wi-Fi** networks.
- **Displays** — display information. Note: **scaling is pinned to 2.0** in
  this release, and there is no display-mode selection yet.
- **Sound** — output device and output volume, and a switch to silence it.
- **Date & Time** — the current time, and the system timezone.
- **Default Apps** — which application handles what, the browser included.
- **Appearance** — the **Dark Mode** switch (the same light/dark choice as the
  desktop right-click menu), **Tiling Windows** to switch between floating and
  tiling window management, the wallpaper picker, the **Screensaver** idle
  time, and a **Notifications** toggle — events collect behind the bell in the
  menu bar.
- **Power** — power options.
- **About** — about the desktop.

---

## Installing more apps

Starling launches applications that are installed on your machine — it does not
bundle them. Two ways to add them:

### Through the App Store

Open the **App Store** from the dock. It lists a curated set of applications —
Chrome, VS Code, Slack, Discord, Teams, Telegram, IntelliJ IDEA, GIMP, Blender,
Spotify, Zoom, and more. Click **Install** on one and Starling installs it
using your system's own `apt` (you may be asked to authenticate — this is
`polkit` authorising the install). When it finishes, the app appears in the
Launchpad and can be pinned to the dock.

A few things to know about the store in this release:

- The catalog is **small and curated** — every entry installs and launches,
  but it is not your whole software library.
- Tiles use **generic category glyphs**, not vendor logos, on purpose — those
  logos are trademarks and Starling ships none of them. Chrome and VS Code show
  their real icons in the Launchpad and dock (read from your system at
  runtime); the rest use a neutral glyph.

### With your distribution's packaging

Anything you install the normal way — `sudo apt install <package>`, a `.deb`, a
Snap or Flatpak — is a native Linux app, and Starling will run it as a Wayland
client (or through the in-tree X server for X11 apps). The major toolkits
composite today: Chromium/Electron, Qt6, GTK3 and GTK4.

---

## Workspaces — a desktop for your agent

**Ctrl + ↓** opens **workspace mode** — a room where one app drives and
everything it opens stays beside it. The workspace list is on the left, the
**driver** runs down the middle, and every window the driver opens lands as a
**tab** on the right — never on your desktop. **Ctrl + ↓** again (or
**Workspace** in the desktop menu) steps back out to the desktop you came
from; the workspace and its apps keep running, and the same key leads back in.

It is built for handing work to an AI agent — coding is the demo, not the
boundary: start a terminal as the driver, run an agent in it, and whatever
the agent opens to do its job — browsers, editors, documents — stacks up as
tabs in its room while your own windows never move. You can watch, and you
can step in — click into any pane and use it like any other window. There is
a three-minute recording of a coding agent doing exactly this on
[starling.build](https://starling.build/#agents).

Working the room:

- **+ New** (top of the list) creates a workspace and opens its name for
  editing in place — type and press **Enter** (**Esc** keeps the old name).
  Rename later from the **pencil** on the row you are pointing at, or
  right-click the row.
- An empty workspace shows **Choose an app to work in** — pick the driver.
- Drag the divider between the driver and the tabs to change the split.
- Right-click a tab to **Move to Desktop** (the window leaves the room) or
  **Close** it.
- The **trash** on a hovered row opens the same menu as a right-click, which
  holds the two ways out: **Remove** moves the workspace's windows to your
  desktop and drops the row; **Delete** stops every app in it. Both sit
  behind the menu on purpose — a stray click on a hover button must not be
  able to stop your agent's apps.
- Each monitor has its own workspace mode: **Ctrl + ↓** acts on the monitor
  the pointer is on and leaves the others alone.

---

## Things to know in this release

Starling is an early preview (v0.3.0). A few limits you will notice:

- **No screen lock.** There is a screensaver (below), but it is decoration:
  any key or mouse movement dismisses it, with nothing asked. Do not rely on
  it to secure an unattended machine.
- **Every display scales the same.** The session picks one scale for the whole
  desktop, from the primary panel's pixel density, and Settings → Displays
  moves it in 0.25 steps (fractional scales included — 1.25 and 1.5 render as
  crisply as 2.0). A second monitor of a different density therefore shares
  the first one's scale; per-display scale is not implemented yet.
- **Changing the scale does not rescale apps already open.** The desktop and
  Starling's own apps follow immediately; a third-party Wayland app keeps the
  size it started at until you restart it.
- **No display-mode picker.** The session uses the connector's preferred mode.
- **Zoom runs without audio.** It starts and reports `no pactl and pacmd
  found`. That message is expected: `pactl` is deliberately left off the system
  because Zoom crashes at startup when it is present. **Do not install
  `pulseaudio-utils` to fix it** — that trades a silent Zoom for one that will
  not start. Sound in other apps (Chrome, Slack, Teams) is unaffected.
- Verified on **AMD** and **virtio-gpu** graphics, and on **NVIDIA** as the
  second GPU of a hybrid laptop (per-app render offload). Intel, and NVIDIA
  driving the desktop itself, are not yet tested.

If something misbehaves, the session log is at
`/tmp/starling-session-<your-uid>.log`, and issues go to
<https://github.com/starling-build/starling/issues>.

---

*See also: the [Installation Guide](INSTALL.md), and the project
[README](../README.md) for the technical picture and what does and doesn't work
yet.*
