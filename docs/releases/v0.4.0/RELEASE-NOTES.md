# Starling 0.4.0 — pick how it looks, and pay nothing when you are not using it

Two and a half weeks and 649 commits since 0.3.0. Two things changed that you
will notice within a minute of logging in: **the desktop has more than one
look now**, and **it costs almost nothing when you leave it alone**.

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

## Remote and headless

The desktop runs on machines with no graphics hardware at all, over RDP, and
that path is now gated on every release. Connect from anywhere; the remote
screen *is* the display. It honours the style you picked (it did not before —
it always came up macOS), and with nobody connected the listener costs nothing.

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

## Install

```bash
curl -fLO https://github.com/starling-build/starling/releases/download/v0.4.0/starling_0.4.0_amd64.deb
sudo apt install ./starling_0.4.0_amd64.deb
```

Ubuntu 26.04. Log out, pick **Starling** from the session menu, log back in.
