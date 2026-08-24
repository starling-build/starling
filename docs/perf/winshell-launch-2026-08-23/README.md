# Start menu and file manager launch: ours vs the Windows shell — 2026-08-23

The two comparison films from the launch-latency round, kept with the round
they came from. The analysis and the launch budget behind them are the
addendum in `docs/plans/winshell-perf.md`; this directory holds the artifacts
and the injector's stamps.

- `ui/video/start-latency.mp4` — Win key to a drawn Start menu, 1/8 speed.
  Poster: `ui/img/start-latency-poster.jpg`.
- `ui/img/start-latency-filmstrip.png` — every composited frame after the Win
  key, both shells, labelled in milliseconds.
- `ui/video/file-launch.mp4` — Win+E to a usable file window, 1/6 speed.
  Poster: `ui/img/file-launch-poster.jpg`.

Rig: `test/bench/win-latency/` (`capture-menu.ps1`, `capture-launch-winE.ps1`
→ `extract.sh` → `analyze-menu.py` / `analyze-launch.py` → `compose-*.py`).
Physical box, 4K at 200%, 30 Hz panel — one composited frame is 33 ms.

## What the films show

Keystroke to pixels, warm, medians of 6:

| | first pixels | usable |
|---|---|---|
| Start menu — Starling | 67 ms | **67 ms** (same frame, no animation) |
| Start menu — Windows 11 | 183 ms | **300 ms** (fades in over ~4 frames) |
| File manager — Starling Files | 317 ms | **500 ms** |
| File manager — Windows Explorer | 366 ms | **1149 ms** |

Re-run at n=20 with both launched by the same `CreateProcessW` and both on
our shell — which is the honest question, since that is where a user of this
desktop actually opens a file manager:

| | first pixels | usable | p25–p75 (usable) |
|---|---|---|---|
| Starling Files | **300 ms** | **483 ms** | 467–500 |
| Windows Explorer | 567 ms | **1400 ms** | 1308–1400 |

**4.5× to a finished Start menu; 2.3–2.9× to a usable file window** — the
latter while starting a whole process, which Explorer running as the shell
never does. The distributions do not touch: our slowest of twenty (600 ms)
beats Explorer's fastest (1300 ms).

Why Explorer has two numbers, since quoting either without the other is
misleading: `explorer.exe` is one binary with two roles, and which one is
running decides what a folder window costs. As the shell, a folder window is
hosted in the already-running process and creates no process at all (1149 ms).
Not the shell — i.e. on our desktop — each folder window becomes its own
process (1400 ms). Both sides pay process creation there, which is why that is
the comparison the film shows.

## Why these were nearly lost

They were produced, sent, and published to an artifact page, and never
committed — they sat in a session scratchpad on tmpfs for a day. The rig was
in the repo; its output was not. Anything worth showing twice belongs in
`ui/video`, next to the films that were already there.
