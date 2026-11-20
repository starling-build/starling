#!/bin/bash
# Lazy blame, run by render-gate.sh after a clean pass; never fails the PR (the caller ignores the exit code).
# The gate compares head with base. This also compares the BASE scores of the rendered docs with the stored baseline
# (/data/landq/base/linux, absolute versus Word). For a doc where the base is below the baseline, walk back over the
# main commits that have a cached binary (renders only, no builds), find the first commit that is below the baseline,
# then open an issue naming it, its PR and the docs, and add a line to the coordinator log.
# env: W (gate scratch, holds pair/), LQ, BC (binary cache), BASE_SHA, EO, JOBS
set -u
BL=$LQ/base/linux; BADL=$W/blame.bad; : > "$BADL"
for f in "$W"/pair/work/base-*/match-v2.txt; do
  [ -f "$f" ] || continue; S=${f%/match-v2.txt}; S=${S##*/base-}; [ -f "$BL/$S.v2" ] || continue
  awk -v S="$S" 'NR==FNR{if($0 ~ /%  lines /){b[$NF]=$1+0}; next} /%  lines /{id=$NF; if((id in b) && $1+0 < b[id]-0.05) print S, id, $1+0, b[id]}' "$BL/$S.v2" "$f"
done > "$BADL"
N=$(wc -l < "$BADL"); [ "$N" -gt 0 ] || { echo "render-gate blame: base is at or above the baseline on every rendered doc"; exit 0; }
echo "render-gate blame: $N doc(s) where base is below the baseline"
cut -d' ' -f2 "$BADL" | sort -u > "$W/blame.ids"
bad() {  # $1 = commit sha with cached binary: is any blamed doc below baseline there?
  local bin=$BC/$1/release/OfficeApp st=$W/blame-stage-${1:0:9}; rm -rf "$st"
  ( export SWEEP_ONLY=$W/blame.ids; ENGINE_OUT=$EO STAGE=$st BASE_SCORES= BASE_REV=$1 SCORES_BASE=/nonexistent JOBS=${JOBS:-32} \
    test/tools/docx-pair.sh "$bin" "$bin" "${JOBS:-32}" > "$st.log" 2>&1 ) || return 2
  local r=1 f S
  for f in "$st"/work/fix-*/match-v2.txt; do [ -f "$f" ] || continue; S=${f%/match-v2.txt}; S=${S##*/fix-}
    awk -v S="$S" 'NR==FNR{if($0 ~ /%  lines /){b[$NF]=$1+0}; next} /%  lines /{id=$NF; if((id in b) && $1+0 < b[id]-0.05) f=1} END{exit f?0:1}' "$BL/$S.v2" "$f" && r=0
  done
  rm -rf "$st"; return $r
}
FIRSTBAD=$BASE_SHA; STEPS=0; LASTGOOD=""
for c in $(git rev-list --first-parent "$BASE_SHA~1" -n 200 2>/dev/null); do
  [ -x "$BC/$c/release/OfficeApp" ] || continue
  STEPS=$((STEPS+1)); [ $STEPS -le 8 ] || break
  bad "$c"; rc=$?
  if [ $rc = 0 ]; then FIRSTBAD=$c; elif [ $rc = 1 ]; then LASTGOOD=$c; break; else echo "render-gate blame: render failed at ${c:0:9}"; break; fi
done
if [ -n "$LASTGOOD" ]; then WHERE="first below the baseline: ${FIRSTBAD:0:9} (last good with a cached binary: ${LASTGOOD:0:9})"
else WHERE="no cached binary at or above the baseline within $STEPS step(s); earliest checked bad: ${FIRSTBAD:0:9}"; fi
SUBJ=$(git log -1 --format=%s "$FIRSTBAD" | cut -c1-120)
PRN=$(gh api "repos/${GITHUB_REPOSITORY:-}/commits/$FIRSTBAD/pulls" --jq '.[0].number' 2>/dev/null || true)
DOCS=$(head -15 "$BADL" | awk '{printf "%s %s (%s vs baseline %s)\n",$1,$2,$3,$4}')
BODY=$(printf 'Lazy blame from the render gate of %s.\n\nThe base (%s) renders below the stored baseline on %s doc(s).\n%s\nCommit: %s %s\nPR: %s\n\nDocs (first 15):\n%s\n' "${GITHUB_SHA:-?}" "${BASE_SHA:0:9}" "$N" "$WHERE" "${FIRSTBAD:0:9}" "$SUBJ" "${PRN:+#$PRN}" "$DOCS")
if [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  # one issue per blamed commit
  gh issue list --repo "$GITHUB_REPOSITORY" --search "blame ${FIRSTBAD:0:9} in:title" --state open --json number --jq '.[0].number' 2>/dev/null | grep -q . ||
    gh issue create --repo "$GITHUB_REPOSITORY" --title "render drop vs baseline: blame ${FIRSTBAD:0:9}" --body "$BODY" >/dev/null 2>&1 || true
fi
echo "$(date -u +%FT%TZ) gate blame: $N doc(s) below baseline on main; ${WHERE}; ${SUBJ}; PR ${PRN:-?}; $(cut -d' ' -f2 "$BADL" | head -8 | tr '\n' ' ')" >> "$LQ/to-coordinator.log" 2>/dev/null || true
echo "render-gate blame: $WHERE"; exit 0
