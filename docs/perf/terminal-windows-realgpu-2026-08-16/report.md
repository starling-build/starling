# Real hardware at last — and the first Windows round we win outright

2026-08-16, on **real hardware rather than a VM**: a Ryzen 7 8845HS laptop
(8 cores / 16 threads, 28.8 GB) driving a Dell P2715Q off its Radeon 780M.
Ours is the 0.1.0 release candidate carried in `dist/` — the binary stamped
2026-08-15 08:56:26, sha256 verified against `dist/SHA256SUMS` before
unpacking. Every earlier Windows round ran in a libvirt guest on QXL; this is
the first with a real GPU, a real panel and a real compositor under both
terminals.

**We win every test.** The ten-workload suite runs in 0.72x of Windows
Terminal's wall time on 0.50x of its CPU, both `cat` tests are wins, and
DOOM-Fire — our clearest loss on every VM round — inverts to a 1.25x win.

| test | ours | Windows Terminal | ours/WT |
|---|---|---|---|
| suite, 10 workloads (s) | **1576.2** | 2184.8 | **0.72x** |
| suite CPU (s) | **1903.3** | 3818.5 | **0.50x** |
| suite RSS | **69.9 MB** | 1026.0 MB | **0.07x** |
| `cat` 500 MB ascii (s) | **3.21** | 3.77 | **0.85x** |
| `cat` 500 MB unicode (s) | **7.51** | 11.36 | **0.66x** |
| DOOM-Fire (fps, higher better) | **487** | 390 | **1.25x** |
| DOOM-Fire CPU (s) | **373.1** | 700.6 | **0.53x** |

| workload | ours (s) | WT (s) | ours/WT | CPU ours | CPU WT |
|---|---|---|---|---|---|
| 01_light_cells | 151.6 | 182.7 | 0.83x | 180.9 | 345.8 |
| 02_dense_cells | 155.3 | 182.7 | 0.85x | 199.8 | 289.8 |
| 03_sgr_fg | 187.4 | 221.2 | 0.85x | 207.7 | 437.4 |
| 04_sgr_truecolor | 183.6 | 185.7 | 0.99x | 214.8 | 326.2 |
| 05_unicode | 169.6 | 231.8 | 0.73x | 241.3 | 433.8 |
| 06_cursor_motion | 191.9 | 250.1 | 0.77x | 223.6 | 461.6 |
| 07_alt_screen | 139.0 | 248.6 | **0.56x** | 164.5 | 409.3 |
| 08_scroll_region | 180.4 | 304.1 | **0.59x** | 191.5 | 597.0 |
| 09_long_lines | 176.0 | 201.5 | 0.87x | 235.6 | 308.2 |
| 10_binary | 41.4 | 176.2 | **0.24x** | 43.5 | 209.5 |

Raw in `data/`. Both onset probes `VERDICT flat`, grid verified 40x120 on
both sides at every leg, every leg first attempt, and `cpuref` — a fixed
compute loop timed inside each leg — reads 0.416 for ours against 0.422 for
WT, so both sides were measured with the machine in the same state.

## What the numbers say

- **`10_binary` is a 4.3x win** — 41.4 s to 176.2 s — the widest gap in any
  Windows round so far, ours or theirs. Nothing here explains it, which makes
  it the most interesting open lead on this platform.
- **`07_alt_screen` (1.79x) and `08_scroll_region` (1.69x)** come next. Both
  are workloads where the terminal must move or discard large regions rather
  than append, which is where a scrollback implementation shows.
- **`04_sgr_truecolor` is the one dead heat** (0.99x) — worth noting because
  it is the shape of work DOOM-Fire does, and DOOM-Fire is a clear win. Wide
  colour is not what separates these two terminals.
- **CPU is the widest column: 0.50x overall**, and 4.8x on `10_binary`. We
  are not buying wall-clock with cores — we finish first *and* burn half.
- **Memory is the outlier result: 69.9 MB against 1,026 MB.** Windows
  Terminal's suite RSS is the same ~1 GB the 08-15 VM round measured, so it
  reproduces across machines and it is not an artifact of this box. Ours is
  70 MB here against 29 MB there, because this round draws 4x the pixels.
- **Unicode is no longer our weakness anywhere.** `cat 500 MB unicode` is
  0.66x and `05_unicode` is 0.73x. On Linux this was our standout weakness —
  last of five terminals, 2.3x behind ghostty — before that gap was closed.
- **DOOM-Fire inverts.** 487 fps against 390, on half the CPU. It was 0.80x
  on the win11 VM and 0.92x on the fresh VM, and those rounds made "latency
  in our frame path" the standing open lead on Windows. On real hardware that
  lead closes and reverses. Going from the VMs' 39x120 at 100% scale to
  40x120 at 200% is roughly 4x the pixels, and Windows Terminal gives up far
  more to that than we do.
- **Ours is unusually stable.** Across every configuration measured today —
  locked and unlocked, 10-repetition legs and 123-repetition legs, fresh
  process and eighth-workload-in — ours never moved more than 2% per
  repetition on any workload. That is worth having on the record next to the
  throughput numbers.

## The box, and three deviations from earlier rounds

    Windows 11 Pro 26200, Ryzen 7 8845HS (8c/16t), 28.8 GB
    Radeon 780M, driver 32.0.13031.8021
    Dell P2715Q, 3840x2160 @ 30 Hz, 200% scale

- **Windows Terminal *Preview* 1.25.1912.0, not the 1.24.11911.0 stable of
  every earlier round.** Forced, not chosen: WT 1.24 hosts every window in
  one process, and `wt.exe`, `wt -w new`, `wt -w -1` and the packaged
  `WindowsTerminal.exe` by full path all hand off to the process already
  running. Where the operator's own shell is a Windows Terminal, the
  benchmark window lands *inside it* — its CPU delta then carries whatever
  that shell is doing, and its RSS is the whole process's working set. The
  08-15 VM never hit this (pre-existing WT 4544, measured leg 2092). Preview
  is a separate package with a separate process, so it isolates cleanly.
  Within this round ours-vs-WT is fair; **across rounds the WT column is a
  different build**.
- **40x120, back up from the fresh VM's 39x120**, which was a 1280x800
  clamp. Ours sized to `STARLING_WINDOW_W=1952 H=1394` device pixels, found
  by probing (`h/probe2.ps1`) rather than computed — at 200% scale the cell
  is 16 x 34.9 device px, and the stock `probe-grid.ps1` cannot find it,
  because its candidate cells are the 8-9 x 17-19 of a 100% desktop.
- **The panel runs at 30 Hz**, its only listed 4K mode — it is on HDMI 1.4
  bandwidth. Both terminals face the same cap so the comparison holds, but
  DOOM-Fire measures per-frame turnaround, so a 4K60 leg over DisplayPort is
  the obvious next thing to run.

## Reproducing

Everything needed is in this directory plus `dist/`. About 20 minutes of
setup, then 1h45m for the round (or 8 minutes with `-Short`):

    # 1. the terminal under test
    Expand-Archive dist\starling-terminal-windows-x86_64.zip C:\dist\TerminalApp

    # 2. corpora (suite at the round's grid, then the 500 MB pair)
    python test\bench\gen-bench.py C:\bench 120 40
    python h\gen-bigcat-win.py C:\bench

    # 3. DOOM-fire, cross-platform via zig, no MSVC toolchain needed
    #    const-void/DOOM-fire-zig at eb0631b, plus both patches
    git apply -p1 --ignore-whitespace ..\terminal-vs-ghostty-2026-08-04\doom-fire-bench.patch
    git apply -p4 --ignore-whitespace ..\terminal-windows-published-2026-08-12\doom-fire-windows.patch
    zig build -Doptimize=ReleaseFast      # zig 0.14.1; 0.16 will not build it
    copy zig-out\bin\DOOM-fire.exe C:\doomfire\

    # 4. the rival, isolated in its own process
    winget install --id Microsoft.WindowsTerminal.Preview -e --source winget

    # 5. verify the grid on both sides, then run
    h\probe2.ps1 -Target 40x120 -W @(1952) -H @(1394)
    h\bench-long.ps1                 # 1h45m;  -Short for the ~8 min version

`--ignore-whitespace` on both patches is required, not optional: they carry
trailing-whitespace differences against the upstream tree, and `git apply`
rejects them with only "patch does not apply" to go on.

`-Short` sizes each workload to ~12 s on the slower side instead of >=120 s,
with DOOM at 20k frames and bigcat at 2 reps. Every workload holds a
rep-to-rep spread under 3% and the per-rep curves are flat from the first
repetition, so the shortening costs precision this comparison never used —
but quote long-round numbers when comparing against the archived rounds,
which were all taken at >=120 s.

## Two things the harness now records, and why

- **`workstation locked: <bool>`**, second line of every round log. The first
  full round of the day was measured with the session locked and nobody knew
  until afterwards, when verification screenshots came back solid black. It
  turned out not to matter — that round (`data/first-round-locked/`) agrees
  with this one to within 3% on every test, 0.69x against 0.72x on the suite
  and 1.28x against 1.25x on DOOM — but that was luck, not method.
- **`cpuref=`** in every suite leg header: a fixed integer loop, timed. It
  touches no I/O and no terminal, so it moves only when the machine's compute
  throughput moves. One 14-minute leg during the day produced Windows
  Terminal numbers 10-36% faster than six other runs of the same thing and
  nothing in the data could say why — the lock screen, leg length, occlusion
  (measured directly: 2.446 s/rep foreground against 2.404 occluded),
  cumulative bytes since launch, memory, and `% Processor Performance` were
  all ruled out. That counter reads ~79% on this box whether idle or
  saturated, so it cannot answer the question; `cpuref` can. Controls in
  `data/reproduce-unlocked/`.

## What this round does not settle

- **Why `10_binary` is 4.3x.** The widest gap on the platform, unexplained.
- **What made that one WT leg 10-36% fast.** Bounded, non-reproducing across
  six runs, and now detectable via `cpuref`, but not identified.
- **60 Hz.** Every number here is under a 30 Hz present cap, and DOOM-Fire is
  the test most likely to move.
- **Whether Preview and stable differ.** The WT column is 1.25 Preview. A
  stable-vs-Preview leg on a box with no Windows Terminal in the operator's
  own session would say whether any of this is a build difference rather than
  a terminal difference.
