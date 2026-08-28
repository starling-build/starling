# Shell latency, all three arms — 2026-08-27, n=20, stock CPU settings

The take behind the site's Windows-page films and
`docs/plans/winshell-perf.md`'s 2026-08-27 addendum. Same rig as
`test/bench/win-latency/` (ddagrab + sync marker), 20 warm reps a side,
medians, each shell registered as THE shell while it was filmed, the box on
its as-shipped CPU cap (min 80 / max 50 / boost off, Balanced — the only
mode that survives sustained load on this machine).

| | first pixels | finished | ratio (finished) |
|---|---|---|---|
| Start menu — Starling | 100 ms | **100 ms** | — |
| Start menu — Windows 11 | 167 ms | **300 ms** | **3.0×** |
| Right-click menu — Starling | 67 ms | **67 ms** | — |
| Right-click menu — Explorer | 233 ms | **267 ms** | **4.0×** |
| Win+E file manager — Starling | 83 ms | **83 ms** | — |
| Win+E file manager — Explorer | 367 ms | **1116 ms** | **13.4×** |

`bench-native-clean` is a re-capture of the Windows Start-menu side from the
evening of the 27th: the first native take had a File Explorer window sitting
open behind all 20 reps (left over from the Win+E benchmark), which is a
cosmetic problem for a published film even though it is not a measurement
one — the clean-desktop re-run reproduced the medians EXACTLY (first 167,
settled 300), which is itself evidence the background window never moved the
number. The films use the clean take; `analysis-menu-native.txt` is the
contaminated original, kept for that comparison.

The `analysis-*.txt` files are `analyze-menu.py` / `analyze-launch.py`
output over the captures (the .mkv files live on the box in `C:\st`, ~850 MB
— stamps and analyses are the record here). Calibration 0.9998–1.0002
throughout; every distribution is disjoint from its opponent's.
