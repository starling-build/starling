# TerminalApp on Windows — first perf look, and it is not close

2026-08-11, the win11 libvirt VM (4 vCPU, QXL display at 1280x800), current
main (C core + extent blanking + wide cells + grapheme clusters) built with
`sdk/tools/build-windows.ps1 -Configuration release` against the Aug-5
host_release engine. One source fix was needed: `PtyWindows.swift` still
had the pre-split `onData([UInt8])` surface; it now matches the POSIX
side's zero-copy `(UnsafePointer<UInt8>, Int)`.

There is no ghostty on Windows (macOS/Linux only), so the rival is
**Windows Terminal** — the default, and the only other terminal the VM can
run: alacritty installs but needs OpenGL 3.3+, which the QXL adapter does
not provide (WT survives on DirectX/WARP).

Protocol: both terminals at exactly **120x40** (ours via
`STARLING_WINDOW_W=960/H=620` — Windows font metrics give different cell
sizes than Linux, so the pixel request was calibrated empirically; WT via
`--size 120,40`), corpus regenerated for that grid
(`gen-bench.py C:\bench 120 40`), `test/bench/windows-runner.ps1` run
inside each terminal via the interactive scheduled task, `cmd /c type` as
the writer. Single rep — the gaps dwarf rep noise. Raw: `data/`.

| workload | ours | Windows Terminal | ours/WT |
|---|---|---|---|
| 01_light_cells | 10.47 | 4.52 | 2.3x |
| 02_dense_cells | 8.65 | 7.05 | 1.2x |
| 03_sgr_fg | **248.6** | 17.96 | **13.8x** |
| 04_sgr_truecolor | 34.8 | 27.8 | 1.3x |
| 05_unicode | 18.5 | 14.2 | 1.3x |
| 06_cursor_motion | 1.53 | 1.50 | 1.0x |
| 07_alt_screen | 18.5 | 8.12 | 2.3x |
| 08_scroll_region | 37.4 | 18.3 | 2.0x |
| 09_long_lines | 11.96 | 9.40 | 1.3x |
| 10_binary | 21.6 | 13.9 | 1.6x |

Context that keeps these numbers honest:

- **Everything is 20-1000x slower than Linux for BOTH terminals** — ConPTY
  interprets the writer's output into its own buffer and re-emits a
  synthesized VT stream, and that pipeline, not the terminal, sets the
  scale (Linux sgr_fg: 0.26 s; WT: 18 s). Relative numbers still
  discriminate: WT beats us everywhere.
- **Our Windows path has had zero performance work.** Every optimization
  round to date was Linux: the reader here is the pre-split serial loop
  (no ChunkRing, no drain-into-slot), and none of the read-path findings
  have been ported.
- **sgr_fg at 248.6 s (42 s terminal CPU, the rest stalled) is a
  pathology, not a throughput number** — 0.17 MB/s. Something in our
  ConPTY path goes quadratic-or-timeout-shaped on escape-dense
  re-synthesized streams; first suspects are per-chunk repaint scheduling
  against Foundation-on-Windows timer resolution, and the
  read-parse-repaint serialization the Linux split removed. Diagnose
  before optimizing anything else here.

The port itself is healthy: current main builds with one signature fix,
runs, renders PowerShell, and survives the full corpus. The perf story is
where Linux was in early August, pre-round-9: unmeasured until today, and
now measured to be the next project.
