# Starling 0.4.0 — runs on Windows through WSL, picks how it looks, and costs nothing idle

Two and a half weeks and 649 commits since 0.3.0. Three things changed that
you will notice: **the desktop runs on a Windows machine through WSL**, **it
has more than one look**, and **it costs almost nothing when you leave it
alone**.

## It runs on Windows, through WSL

**[Watch the walkthrough (2:27)](../../../ui/video/wsl-walkthrough.mp4)** —
install, start, connect, use it. Recorded end to end on a real Windows machine;
nothing in it is faked or sped up.


You do not need a Linux machine to run Starling any more. Install WSL on
Windows, install the `.deb` inside it, and connect with any RDP client —
Windows' own Remote Desktop will do. The whole desktop comes up: the shell,
the dock or taskbar, the apps, the file manager, the terminal.

This works because WSL has no graphics device *at all* — not an empty one, an
absent one — so the desktop takes a different path entirely. **The remote
screen becomes the display.** There is no local window being mirrored to you;
the RDP surface is where the desktop is drawn in the first place, in software,
and what you connect to is the real thing rather than a copy of it.

It is a supported platform now, not an experiment. It has its own gate that
runs on every release, on real WSL on a real Windows machine — eleven checks
covering that the package installs on a clean Ubuntu, that the shell starts
with no GPU, that a real client connects and is activated, that **the pixels
it receives are an actual desktop** rather than a black rectangle, and that
the session leaves the shell alive and back at idle afterwards.

Three things that are true of it and were not before:

- **It honours the style you picked.** It used to come up macOS whatever you
  had chosen, because the code that restores your choice only ran on the
  graphics path. Both styles work over RDP now.
- **Idling costs nothing.** With the listener up and nobody connected, the
  desktop uses 0.00% of a core. The listener used to wake five times a second
  just to notice if it had been asked to stop.
- **It behaves the same as the local desktop**, because it is the same
  desktop — same shell, same apps, same package.

The same path serves any headless Linux box: a machine in a cupboard with no
monitor runs the full desktop and you connect to it.

## The desktop has styles

Settings → Appearance → **Desktop Style**. Two of them today: the macOS one
you already had, and a Windows 11 one. The whole desktop rebuilds into your
choice and remembers it across a relogin.

This is a change of *shape*, not a repaint. In the Windows style there is no
menu bar along the top; the taskbar runs the full width of the screen edge and
reserves its space, so a maximised window stops above it rather than sliding
under. Start is a panel that opens above the bar instead of a full-screen
grid. Window buttons move to the right and become the caption trio, with the
close button turning Microsoft's red when you point at it. Hovering a taskbar
tile shows a **live preview** of that window — the real thing, updating, not a
thumbnail taken when it opened.

The colours are not eyeballed. They come from WinUI's own resource dictionary,
by name, the same values our Windows shell uses. The chrome takes a tint from
your wallpaper the way Mica does. Text is Selawik, Segoe UI's metric-compatible
stand-in, which we can actually ship.

**The first-party apps follow the style too** — Files, Settings, the terminal,
the rest. They were ten separate hand-written palettes of the same shape; now
they share one, and it points at whichever style is active.

Adding a third style is one file and one line. There is deliberately no
`if style == …` anywhere else in the shell.

## It stops working when you stop working

An idle Starling desktop used to spend **1.40% of a CPU core** doing nothing in
particular. It now spends **0.02%** — seventy times less. On a laptop that is
the difference between the desktop being a background cost and not being one.

Everything that used to run on a timer now waits to be told:

- The frame pump asked recording, screen sharing and RDP thirty times a second
  whether they needed anything. They say so themselves now, and it does not
  run at all when nobody is listening.
- The compositor's own event loops — two of them — woke sixteen milliseconds
  apart forever to re-check flags. They sleep until something happens.
- The two D-Bus services woke five times a second each for the same reason.
- The battery was read from the system every five seconds, which is more
  expensive than it sounds: asking a laptop whether it is plugged in makes the
  kernel interpret firmware bytecode. The kernel tells us now.

**One bug fell out of that, and it is worth naming**: with nothing polling any
more, nothing redrew the shell — so the clock stopped. It sat at whatever time
you last touched the machine. The clock keeps its own cadence now, wakes on the
minute, and redraws only itself. The same was true of the blinking cursor in
the search box, which had been redrawing the entire desktop twice a second;
leaving Start open cost 2.35% of a core and now costs 0.8%.

## Also in this release

- **Live window previews** on taskbar hover, mipmapped so they are legible
  rather than aliased.
- **Maximise and minimise behave like Windows** in the Windows style — maximise
  fills to the taskbar rather than going fullscreen.
- The terminal, the file manager and the SDK behind them all moved forward
  considerably; see the log for detail.

## Gates

Cut from `release-0.4.0`, which is the branch name in **both** repos — the
desktop's and the engine's. Checking out that one name in each gets you a
buildable pair.

- static + unit tier: pass
- functional tier on a live desktop, **including real App Store installs**:
  25 passed. Chrome and VS Code install from scratch and launch from the
  Launchpad; a third-party window resolves to its app; removal drops it again.
- WSL gate (RDP display mode, no GPU): 11 of 11
- release gate: the `.deb` on a clean VM through a real GDM login

## Fonts and licences

The Windows style draws with **Fluent UI System Icons** (MIT, Microsoft's own
published binary, redistributed unmodified) and sets its text in **Selawik**
(SIL Open Font License 1.1) — Microsoft's metric-compatible stand-in for Segoe
UI, published for exactly this use. Neither Segoe UI nor Segoe Fluent Icons is
redistributed: those are Windows system fonts, and our Windows shell reads them
off the machine it runs on rather than shipping them.

Every licence that requires its text to travel with the files now does. The
package installs them under `/usr/share/doc/starling/`, and `NOTICE` is the
index. Fluent is a trademark of Microsoft; the style is named for the design
language it follows, and this project is not affiliated with or endorsed by
Microsoft.

## Install

```bash
curl -fLO https://github.com/starling-build/starling/releases/download/v0.4.0/starling_0.4.0_amd64.deb
sudo apt install ./starling_0.4.0_amd64.deb
```

Ubuntu 26.04. Log out, pick **Starling** from the session menu, log back in.
