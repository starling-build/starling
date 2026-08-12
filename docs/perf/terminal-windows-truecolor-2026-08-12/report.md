# sgr_truecolor on Windows: not a regression, a 29x change in chunk size

`04_sgr_truecolor` was the one workload the OpenConsole host switch made
slower — 23.89 -> 26.34 s, +10.3% — and the only thing on Windows that looked
like a regression we had introduced. It is not one, and the mechanism is worth
knowing because it is invisible from wall time.

## Measurements

Profiled by process (one rep, 40x120, `profile-doom.ps1`'s sibling
`profile-run.ps1`), then the delivered stream counted in the reader itself:

| | wall | **our CPU** | host CPU |
|---|---|---|---|
| inbox conhost | 24.78 | **15.53** | 12.88 |
| OpenConsole | 26.62 | **22.09** | 12.44 |
| Windows Terminal (OpenConsole) | 25.82 | **21.31** | 13.98 |

| host | bytes delivered | chunks | avg chunk |
|---|---|---|---|
| inbox conhost | 67,120,588 | 31,402 | **2,137 B** |
| OpenConsole | 67,108,995 | 915,866 | **73 B** |

(Corpus is 67,110,000 bytes, so both hosts pass it through ~1:1.)

## What it means

- **The host is not more expensive**: 12.88 vs 12.44 CPU-seconds. Whatever
  OpenConsole is doing differently, it is not costing *itself* more.
- **The bytes are identical** to within 0.02%. It is not sending more.
- **It sends them in 29x more pieces**, 73 bytes at a time instead of 2137.
  Every piece costs a ring pass, an emulator lock and a repaint schedule, and
  that is the whole of our +42% CPU (15.53 -> 22.09).
- **Windows Terminal pays the same price**: 21.31 CPU-seconds against our
  22.09, on the same host, and lands within 3% of us on wall. So this is not
  an inefficiency of ours relative to the reference consumer — it is the shape
  of the stream, and both terminals eat it.

The drain-into-slot loop that fixed exactly this shape on Linux is already
present here (`starling_conpty_avail` over `PeekNamedPipe`), and it is not
coalescing: it publishes the moment the pipe reads empty, and OpenConsole's
writes are small enough and paced far enough apart that the pipe genuinely is
empty between them. On Linux the same loop collapses ~600-byte reads into
~54 KB slots because the data is already queued.

## Is there anything to do

Not for wall time. Both terminals sit at 25.8-26.6 s, i.e. the workload is
paced by the host, and no consumer-side change moves that.

There is a real **CPU** lever: coalescing small chunks with a bounded wait
(publish immediately when a slot is nearly full or when the wait expires,
rather than the instant the pipe reads dry) should push the average back
toward conhost's 2 KB and recover much of the 6.5 CPU-seconds. The cost is
latency on the keystroke-echo path, which is exactly what the current
"publish when dry" rule protects, so it needs a deliberate bound — a few
hundred microseconds — and a latency measurement to go with the throughput
one. Not attempted here.

## How it was measured

`STARLING_PTY_BYTES=1` makes the Windows reader report cumulative bytes,
chunk count and average chunk size on stderr every 8 MB (branch
`wip-pty-bytes`, diagnostic only, not merged). Reporting has to be periodic
rather than at end-of-stream: with ConPTY the console holds the output pipe
open after the shell exits, so an EOF-triggered report never arrives — the
first version of this probe printed nothing for exactly that reason.

Two earlier attempts at this question were **wrong and are recorded so they
are not repeated**. Both tried to prove the inbox host quantizes colour by
screenshotting a gradient and counting distinct colours: the first cropped a
fixed rectangle and caught desktop wallpaper (8265 vs 347 "colours", pure
framing artifact); the second filled the window but the gradient rendered as a
one-cell strip, so the counts (24459 vs 24434) were again wallpaper. Colour
fidelity was never the difference — chunk size was.
