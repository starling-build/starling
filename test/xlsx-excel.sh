#!/bin/bash
# Open every .xlsx in DIR (or the files given) in Microsoft Excel and say
# whether it opened clean, asked to repair, or could not read it. The Excel
# counterpart of pptx-powerpoint.sh: the oracle for "Excel opens it without
# complaint". Excel must be installed; a first run may need its file-access
# grant for the folder (see driving-powerpoint-mac in the notes).
#
#   test/xlsx-excel.sh DIR|file.xlsx…
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
files=()
for a in "$@"; do
  if [ -d "$a" ]; then while IFS= read -r f; do files+=("$f"); done < <(find "$a" -maxdepth 1 -name '*.xlsx' | sort)
  else files+=("$a"); fi
done
bad=0
for f in "${files[@]}"; do
  out="$(osascript "$HERE/xlsx-excel.applescript" "$f" 2>&1)"
  verdict="${out%%	*}"
  printf '%-10s %s\n' "$verdict" "$(basename "$f")	$(echo "$out" | cut -f2-)"
  [ "$verdict" = clean ] || bad=$((bad + 1))
done
echo "$bad problem(s) in ${#files[@]} file(s)"
[ "$bad" -eq 0 ]
