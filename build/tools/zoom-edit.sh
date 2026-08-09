#!/usr/bin/env bash
# Zoom into a region of a 4K screen recording, for demo edits.
#
# A 3840x2160 capture delivered at 1080p has 2x of zoom in hand: a 1:1 crop is
# pixel-native, so zoomed text is SHARPER than the unzoomed frame, not softer.
# See docs/DEMO.md, "Zooming in".
#
#   zoom-edit.sh IN.mp4 OUT.mp4 PRESET [START] [HOLD]
#
#   PRESET  driver | tabs | full     where to land
#   START   seconds into the clip to begin the move   (default 2)
#   HOLD    seconds the move takes                    (default 1.5)
#
# The `fps` filter before zoompan is load-bearing: the recorder writes VFR
# (capture is damage-driven), and zoompan counts FRAMES, so without it an 8s
# span of a mostly-idle desktop collapses to under 2s of output.
set -euo pipefail

IN=${1:?usage: zoom-edit.sh IN.mp4 OUT.mp4 driver|tabs|full [start] [hold]}
OUT=${2:?missing output}
PRESET=${3:-driver}
START=${4:-2}
HOLD=${5:-1.5}
FPS=30
OUTW=1920
OUTH=1080

# Landing spot as a fraction of the pannable area, at 2x on a 2560x1440
# logical desktop: the rail+driver column occupy the left ~37%, the tab
# column the right ~63%.
case "$PRESET" in
    driver) ZOOM=2.0; FX=0.02; FY=0.02 ;;
    tabs)   ZOOM=2.0; FX=0.78; FY=0.10 ;;
    full)   ZOOM=1.0; FX=0.50; FY=0.50 ;;
    *) echo "unknown preset: $PRESET (driver|tabs|full)" >&2; exit 2 ;;
esac

# Ease from 1x to ZOOM over HOLD seconds, starting at START, then stay there.
Z="min(1+max(0,on/${FPS}-${START})/${HOLD}*(${ZOOM}-1),${ZOOM})"

ffmpeg -hide_banner -loglevel error -i "$IN" -filter_complex \
  "[0:v]fps=${FPS},zoompan=z='${Z}':x='(iw-iw/zoom)*${FX}':y='(ih-ih/zoom)*${FY}':d=1:s=${OUTW}x${OUTH}:fps=${FPS}[v]" \
  -map "[v]" -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart "$OUT" -y

echo "wrote $OUT"
ffprobe -v error -show_entries stream=width,height,nb_frames \
    -show_entries format=duration -of default=noprint_wrappers=1 "$OUT"
