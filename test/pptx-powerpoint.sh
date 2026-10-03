#!/bin/bash
# test/pptx-powerpoint.sh DIR — open every .pptx in DIR in Microsoft
# PowerPoint (macOS) and report, one line each: name, verdict, slide
# count, dialog text. Verdicts: clean, REPAIR ("PowerPoint found a problem
# with content…"), CANTREAD, GRANT (sandbox asked for file access — put
# DIR under $HOME and grant it once), OTHERWIN/ALERT (something else).
# PowerPoint is the fidelity oracle the corpus gate cannot be: a saved copy
# can pass test/pptx-check.py and Quick Look and still be repaired here
# (the OLE and media rounds of 2026-10-03 were found this way). Opens go
# through Launch Services (`open -a`), which grants the sandbox read access
# that an AppleScript `open` of an untouched file does not.
#   python3 test/pptx-corpus.py          # writes ~/.cache/starling/pptx-corpus/out
#   cp ~/.cache/starling/pptx-corpus/out/*.pptx ~/pptx-ppt/ && test/pptx-powerpoint.sh ~/pptx-ppt
DIR=$1; HERE=$(cd "$(dirname "$0")" && pwd)
[ -d "$DIR" ] || { echo "usage: $0 DIR" >&2; exit 2; }
for f in "$DIR"/*.pptx; do
  res=$(osascript "$HERE/pptx-powerpoint.applescript" "$f" 2>&1)
  printf '%s\t%s\n' "$(basename "$f")" "$res"
done
