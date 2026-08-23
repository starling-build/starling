#!/bin/bash
# Per-frame signals from a capture, for the analyzers.
#
#   extract.sh <video> <prefix> <marker-crop> <region-crop> [grid]
#
# marker-crop / region-crop are ffmpeg crop expressions (w:h:x:y) in the
# CAPTURE's coordinates, not the screen's. `grid` is the region signature
# resolution: 16 is enough to see a menu appear, 64 is needed to see a file
# list populate (see README -- 16 flattered Explorer by 400 ms).
set -e
video=$1; prefix=$2; marker=$3; region=$4; grid=${5:-64}
ffmpeg -hide_banner -loglevel error -i "$video" \
  -vf "crop=$marker,scale=1:1,format=gray" -f rawvideo -y "$prefix.marker.raw"
ffmpeg -hide_banner -loglevel error -i "$video" \
  -vf "crop=$region,scale=$grid:$grid,format=gray" -f rawvideo -y "$prefix.region.raw"
echo "$prefix: $(stat -c%s "$prefix.marker.raw") frames, ${grid}x${grid} region signature"
