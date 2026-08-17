# The filmed head-to-head, real hardware

`../starling-vs-windows-terminal-realgpu.mp4` — 64 s, 1080p30, 24 MB. Ours on
the left, **Windows Terminal Preview 1.25.1912.0** on the right, side by side
on one screen, started by the same signal and racing three tests:

| | ours | Windows Terminal |
|---|---|---|
| `cat` 2 GB ascii | **11.64 s** | 14.64 s |
| `cat` 1 GB unicode | **10.22 s** | 17.86 s |
| DOOM-Fire, 6000 frames | **544 fps** | 448 fps |
| **all three** | **39.4 s** | 52.4 s |

Both windows verified at **50x100** before filming — the launcher refuses to
record if the two grids differ, or if they differ from the target. Raw log in
`launch.txt`, the two result lines in `times-ours` / `times-wt`.

The Windows counterpart of `../../terminal-vs-ghostty-2026-08-14-long/film/`
(Linux) and the macOS demo in
`../../terminal-vs-ghostty-macos-2026-08-14-postupgrade/`. The previous
Windows film was shot in the win11 VM; this one is on real hardware.

## Running it

    film-launch.ps1 -Probe            # verify both sides land on the grid
    film-launch.ps1 -OursH 1748 -HideWindowPid <your console pid>

`-Probe` first, always. Ours is sized in **device** pixels
(`STARLING_WINDOW_W/H`) and Windows Terminal in **cells** (`--size`), so the
two only meet at one particular pixel height; at this box's 200% scale that
is 1632x1748 for 50x100, and one row either side of it is a different grid.

`-HideWindowPid` minimises the operator's console — and every other window
over 200x200 — for the duration, then restores them. Without it the capture
shows whatever was on the desktop behind the two terminals, which the first
take proved by filming an Explorer window for 95 seconds.

## Three things this harness learned the hard way

- **ffmpeg is resolved from the film dir first.** A shell started before
  ffmpeg was installed does not have it on `PATH`; `Get-Command` returns
  nothing, the fallback path did not exist, and the race ran perfectly with
  nothing recording it. The first take was lost that way.
- **`ddagrab`, not `gdigrab`.** GDI BitBlt of a 3840x2160 desktop delivers
  about 12 fps of a requested 30 on this box — the video stutters *and* the
  capture burns CPU on the cores being raced. Desktop Duplication holds a
  true 29 fps at 0.99x, and `h264_amf` keeps the encode on the GPU. Also
  `draw_mouse=0`: ddagrab composites the cursor in, and take two has a busy
  spinner parked in the middle of our window throughout.
- **The stale-runner sweep excludes its own pid.** It matches any command
  line containing `race.ps1`, so a caller that merely *mentions* the file
  (`Copy-Item ...\race.ps1 ...; & film-launch.ps1 ...`) matches — and the
  script kills itself. Exit 255, two lines of log, no film. Same trap as
  `pkill -f` matching its own `bash -c` line.

## The code page, which the film is what found

`race.ps1` sets the console to UTF-8 (`chcp 65001`) before streaming. It was
added here first, for a cosmetic reason, and turned out not to be cosmetic.

The corpora are UTF-8 bytes. Without `chcp 65001` the console host
reinterprets every one of them on its inherited legacy code page, and the
unicode test draws `µùÑµ£¼Ð¬` where it should draw 日本語テキスト. Both
terminals receive the identical stream either way, so the race is fair with or
without it — but a film of two terminals racing to render mojibake is a film
of the wrong thing, and that is what the first clean take showed.

It is not a small difference in what is being measured. With the code page
corrected the unicode leg goes from 22.33 s to 17.86 s for Windows Terminal
and from 16.52 s to 10.22 s for us, widening our margin from 1.35x to 1.75x.

**No archived Windows round ever set it**, so every Windows `unicode` figure in
the series is mojibake throughput rather than CJK glyph rendering. The round
has since been re-measured under `chcp 65001`, and that is now the headline
protocol — see "Two protocols" in `../report.md`.
