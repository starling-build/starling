#!/bin/bash
# test/docx-word.sh DIR — open every .docx in DIR in Microsoft Word (macOS)
# and report, one line each: name, verdict, paragraph count, dialog text.
# Verdicts: clean, REPAIR ("Word found unreadable content…"), CANTREAD, GRANT
# (sandbox asked for file access — keep DIR under $HOME and grant it once),
# OTHERWIN/ALERT (something else; rerun the file, it is often transient).
# Word is the fidelity oracle the corpus gate cannot be: a saved copy can pass
# test/ooxml-check.py and still make Word ask to recover it. Opens go through
# Launch Services (`open -a`), which grants the sandbox read access that an
# AppleScript `open` of an untouched file does not.
#   python3 test/docx-corpus.py          # writes ~/.cache/starling/docx-corpus/out
#   cp ~/.cache/starling/docx-corpus/out/*.docx ~/docx-word/ && test/docx-word.sh ~/docx-word
DIR=$1; HERE=$(cd "$(dirname "$0")" && pwd)
[ -d "$DIR" ] || { echo "usage: $0 DIR" >&2; exit 2; }
for f in "$DIR"/*.docx; do
  case "$(basename "$f")" in '~$'*) continue ;; esac   # Word's own lock file
  res=$(osascript "$HERE/docx-word.applescript" "$f" 2>&1)
  printf '%s\t%s\n' "$(basename "$f")" "$res"
done
