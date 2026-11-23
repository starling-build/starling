#!/bin/bash
# merge-watch.sh SHA — after a prebuild of main (amd-8, 2026-11-22). Compares SHA's cached Slides combined.tsv with the nearest earlier main
# commit that has one, and appends every deck that dropped more than 1 point (and the PR(s) merged between the two) to $LQ/to-coordinator.log.
# Reuses the prebuild's output: no render. Needs GH_TOKEN for the PR numbers (falls back to the commit subjects).
SHA=$(git rev-parse "$1") || exit 0; LQ=${LQ:-/data/landq}; LOG=$LQ/to-coordinator.log
# the cache dir is keyed by the ENGINE commit (as render-gate.sh): a fixed key went stale at every engine swap and made this script exit silently (amd-8, 2026-11-23)
if [ -z "${BC:-}" ]; then EN=$(git -c safe.directory='*' -C "${ENGINE_DIR:-/nonexistent}" rev-parse --short=10 HEAD 2>/dev/null) || exit 0; BC=/data/gate/cache/eng-$EN; fi
C=$BC
[ -d "$C/$SHA" ] || exit 0
grep -qs "MERGE-WATCH $SHA" "$LOG" && exit 0
PREV=; for p in $(git rev-list --first-parent -n 60 "$SHA^" 2>/dev/null); do [ -d "$C/$p/rows" ] || [ -s "$C/$p/slides/combined.tsv" ] || [ -s "$C/$p/sheets/per-book.tsv" ] && { PREV=$p; break; }; done
[ -n "$PREV" ] || exit 0
D=$(python3 - "$C/$PREV" "$C/$SHA" <<'P'
# Compares the two cached bases (no render): Slides decks (combined.tsv), Word sample documents (rows/<set>.v2: % of Word's lines matched),
# Sheets books (per-book.tsv: pixel mean and line match). Names what moved WORSE by more than 1 point.
import sys, os, re, glob
a, b = sys.argv[1], sys.argv[2]
def rd(f): return {l.split('\t')[0].rsplit('/',1)[-1]:float(l.split('\t')[1]) for l in open(f) if l.strip()}
out = []
fa, fb = a + "/slides/combined.tsv", b + "/slides/combined.tsv"
if os.path.exists(fa) and os.path.exists(fb):
    x, y = rd(fa), rd(fb)
    for d, k in sorted((y[k]-v, k) for k, v in x.items() if k in y and y[k]-v < -1): out.append("  slides %s %.1f -> %.1f (%+.1f)" % (k[:44], x[k], y[k], d))
rx = re.compile(r"^\s*([\d.]+)%\s+lines\s+(\d+)/(\d+)\s+pages\s+(\d+)/(\d+)\s+(\S+)")
def word(f):
    r = {}
    for l in open(f):
        m = rx.match(l)
        if m: r[m.group(6)] = float(m.group(1))
    return r
for fa in sorted(glob.glob(a + "/rows/*.v2")):
    fb = b + "/rows/" + os.path.basename(fa)
    if not os.path.exists(fb): continue
    x, y = word(fa), word(fb)
    for d, k in sorted((y[k]-v, k) for k, v in x.items() if k in y and y[k]-v < -1): out.append("  word %s %s %.1f -> %.1f (%+.1f)" % (os.path.basename(fa)[:-3], k[:44], x[k], y[k], d))
def sheets(f):
    r = {}
    for l in open(f).read().splitlines()[1:]:
        c = l.split("\t")
        try: r[c[0]] = (float(c[3]), float(c[5]) if c[5] != "-" else None)
        except (ValueError, IndexError): pass
    return r
fa, fb = a + "/sheets/per-book.tsv", b + "/sheets/per-book.tsv"
if os.path.exists(fa) and os.path.exists(fb):
    x, y = sheets(fa), sheets(fb)
    for k in sorted(x):
        if k not in y: continue
        (p0, l0), (p1, l1) = x[k], y[k]
        if p1 - p0 > 1 or (l0 is not None and l1 is not None and l1 - l0 < -1): out.append("  sheets %s pixels %.1f -> %.1f, lines %s -> %s" % (k[:44], p0, p1, l0, l1))
print("\n".join(out))
P
)
[ -n "$D" ] || exit 0
PRS=
for c in $(git rev-list "$PREV..$SHA"); do
  n=$(curl -s -m 20 -H "Authorization: Bearer ${GH_TOKEN:-}" "https://api.github.com/repos/${GITHUB_REPOSITORY:-starling-build/starling}/commits/$c/pulls" 2>/dev/null | python3 -c 'import sys,json
try: print(" ".join("#%d"%x["number"] for x in json.load(sys.stdin)))
except Exception: pass' 2>/dev/null)
  PRS="$PRS $(git log -1 --format='%h' "$c")${n:+($n)}"
done
{ echo "MERGE-WATCH $SHA $(date -u +%FT%TZ): documents (Slides decks, Word sample docs, Sheets books) that got worse by more than 1 point against ${PREV:0:9}; range ${PREV:0:9}..${SHA:0:9}, $(git rev-list --count "$PREV..$SHA") commits in between (hash, PR):$PRS"; echo "$D"; } >> "$LOG" 2>/dev/null
exit 0
