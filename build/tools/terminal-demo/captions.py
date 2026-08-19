#!/usr/bin/env python3
"""Burn drive.py's beat log into the take as subtitles.

    build/tools/terminal-demo/captions.py TAKE.mov beats.json OUT.mp4 \\
        [--lead 2.0] [--end 105] [--cover x,y,w,h[,#rrggbb]]

Captions go in a bar PADDED BELOW the frame, not overlaid on it. An overlay
sits on top of terminal output no matter where you put it — the panes are full
of text to the edges — and a translucent box over live text is unreadable in
both directions.

`--lead` is how long the recording ran before the driver started, since
`screencapture` and `drive.py` are separate processes (deliberately — see
drive.py). `--cover` paints a rectangle before padding: use it for anything the
app itself put on screen that should not be in a shareable video. Claude Code,
for one, prints the account's remaining weekly limit for the first few seconds
of a session. Give it the pane's own background colour, sampled from the frame
rather than taken from the theme (the window is translucent, so what lands in
the file is the composite, not `TerminalTheme.background`):

    ffmpeg -ss 36 -i take.mov -frames:v 1 \\
        -vf "crop=4:4:600:1290,scale=1:1" -f rawvideo -pix_fmt rgb24 - | xxd -p

Menlo, not Arial, for the font: the captions carry ⌘ and ⇧, and Arial has
neither — they render as blank boxes with no warning.
"""
import argparse, json, os, subprocess

FONT = "/System/Library/Fonts/Menlo.ttc"
BAR = 140          # caption bar height, in source pixels
BAR_BG = "0x0A0B10"

ap = argparse.ArgumentParser()
ap.add_argument("take")
ap.add_argument("beats")
ap.add_argument("out")
ap.add_argument("--lead", type=float, default=2.0)
ap.add_argument("--end", type=float, default=0.0, help="trim here; 0 = whole take")
ap.add_argument("--cover", default="", help="x,y,w,h[,#rrggbb] painted before padding")
ap.add_argument("--font-size", type=int, default=44)
args = ap.parse_args()

beats = json.load(open(args.beats))
shown = [b for b in beats if b["text"]]
if not shown:
    raise SystemExit("no captions in the beat log")

probe = subprocess.run(
    ["ffprobe", "-v", "error", "-select_streams", "v:0",
     "-show_entries", "stream=width,height", "-show_entries", "format=duration",
     "-of", "default=noprint_wrappers=1:nokey=1", args.take],
    capture_output=True, text=True).stdout.split()
W, H, DUR = int(probe[0]), int(probe[1]), float(probe[2])
end = args.end or DUR

parts = []
if args.cover:
    f = args.cover.split(",")
    colour = f[4].replace("#", "0x") if len(f) > 4 else "0x14161C"
    parts.append(f"drawbox=x={f[0]}:y={f[1]}:w={f[2]}:h={f[3]}:color={colour}@1:t=fill")
parts.append(f"pad={W}:{H + BAR}:0:0:color={BAR_BG}")

capdir = os.path.join(os.path.dirname(os.path.abspath(args.out)), "caps")
os.makedirs(capdir, exist_ok=True)
for i, b in enumerate(shown):
    start = b["t"] + args.lead
    stop = (shown[i + 1]["t"] + args.lead) if i + 1 < len(shown) else end
    # textfile= rather than text=: the filtergraph parser splits on ':' and
    # ',', both of which appear in ordinary caption prose, and escaping them
    # through a shell as well is how you end up with half a caption.
    path = os.path.join(capdir, f"{i}.txt")
    open(path, "w").write(b["text"])
    parts.append(
        f"drawtext=fontfile='{FONT}':textfile='{path}'"
        f":fontcolor=0xE9EBF0:fontsize={args.font_size}"
        f":x=(w-text_w)/2:y={H + (BAR - args.font_size) // 2 - 6}"
        f":enable='between(t,{start:.2f},{stop:.2f})'")

filt = os.path.join(capdir, "filter.txt")
open(filt, "w").write(",".join(parts))

cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", args.take,
       "-t", f"{end:.2f}", "-filter_complex_script", filt,
       "-c:v", "libx264", "-crf", "21", "-preset", "medium",
       "-pix_fmt", "yuv420p", "-movflags", "+faststart", args.out, "-y"]
r = subprocess.run(cmd, capture_output=True, text=True)
if r.returncode:
    raise SystemExit(r.stderr[-2000:])
print(f"{args.out}  {os.path.getsize(args.out) / 1e6:.1f} MB  {end:.0f}s  {W}x{H + BAR}")
