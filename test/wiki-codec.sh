#!/usr/bin/env bash
# The wiki's stored form, gated (docs/plans/wiki.md W0): every .docx under
# a directory is read, encoded as a page (RichDocumentEnvelope JSON),
# decoded, and compared with what was read — the model must survive its
# own serialisation exactly. A sample of them also goes page → .docx →
# page, and the paragraph ids must come back as written (Word's w14:paraId).
#
#   test/wiki-codec.sh [dir ...]        default: test/corpus/docx
#   OFFICE_APP=<binary>                 default: apps/OfficeApp/.build/debug/OfficeApp
#
# Exit 1 on any DIFF or failure; prints one line per file that is not OK.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="${OFFICE_APP:-$REPO/apps/OfficeApp/.build/debug/OfficeApp}"
[ -x "$APP" ] || { echo "no OfficeApp binary at $APP (swift build --package-path apps/OfficeApp)" >&2; exit 2; }
DIRS=("$@"); [ ${#DIRS[@]} -eq 0 ] && DIRS=("$REPO/test/corpus/docx")
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

ok=0; diff=0; fail=0; skip=0; reader=0; idok=0; idbad=0
while IFS= read -r f; do
    out="$("$APP" --page-roundtrip "$f" 2>"$TMP/err")"; code=$?
    case $code in
        0) ok=$((ok + 1)) ;;
        2) diff=$((diff + 1)); echo "DIFF  $f: ${out#DIFF }" ;;
        1) if grep -q 'unsupported\|corrupt\|unreadable' "$TMP/err"; then
               skip=$((skip + 1))     # the reader refuses it; nothing to encode
           else
               fail=$((fail + 1)); echo "FAIL  $f: $(head -c 200 "$TMP/err" | tr '\n' ' ')"
           fi ;;
        *) # A crash. The reader's (--layout dies the same way) is not the
           # codec's: counted, named, not failed here.
           if "$APP" --layout "$f" >/dev/null 2>&1; then
               fail=$((fail + 1)); echo "FAIL  $f: codec crashed (exit $code) where --layout did not"
           else
               reader=$((reader + 1)); echo "READER $f: the reader itself crashes (exit $code)"
           fi ;;
    esac
done < <(find "${DIRS[@]}" -name '*.docx' -not -name '~$*' | sort)

# Ids through Word's own format: write, read back, compare the id list.
n=0
while IFS= read -r f && [ $n -lt 25 ]; do
    n=$((n + 1))
    "$APP" --page-json "$f" "$TMP/a.json" 2>/dev/null || continue
    "$APP" --page-docx "$TMP/a.json" "$TMP/b.docx" 2>/dev/null || { idbad=$((idbad + 1)); echo "IDS   $f: page-docx failed"; continue; }
    "$APP" --page-json "$TMP/b.docx" "$TMP/b.json" 2>/dev/null || { idbad=$((idbad + 1)); echo "IDS   $f: reread failed"; continue; }
    # Paragraphs flattened out of a kept nested table are written as the
    # XML they came from, which carries no id of ours; compare the rest.
    ids='import json,sys; d=json.load(open(sys.argv[1]))["document"]; print([p["id"] for p in d["paragraphs"] if p.get("keptTable") is None])'
    a="$(python3 -c "$ids" "$TMP/a.json")"
    b="$(python3 -c "$ids" "$TMP/b.json")"
    if [ "$a" = "$b" ]; then idok=$((idok + 1)); else idbad=$((idbad + 1)); echo "IDS   $f: paragraph ids changed through .docx"; fi
done < <(find "${DIRS[@]}" -name '*.docx' -not -name '~$*' | sort)

echo "codec: $ok ok, $diff diff, $fail failed, $skip unreadable, $reader reader crashes; ids through docx: $idok ok, $idbad bad"
[ $diff -eq 0 ] && [ $fail -eq 0 ] && [ $idbad -eq 0 ]
