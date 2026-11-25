#!/bin/bash
# batch-land.sh: lands open PRs in batches, with no model involved (amd-8, 2026-11-24, user direction). Run from cron on the AMD box:
#   */10 * * * * ~/bin/batch-land.sh >> /data/landq/batch-land.cron 2>&1      (the gh login of the box owner opens the PRs: a workflow's own token
#   would not trigger the render-gate run on the batch PR)
# Each run: (A) looks at the batch/auto-* PRs in flight: green -> merge (rebase), close each member "landed in batch #X"; red -> map every dropped
# document to the member whose body or commit names it, park that member and comment the drop (starling-bd approves), then the rest are free for
# the next batch; if nothing names a document, the members are split in halves and retried; a load/timeout failure is rerun once.
# (B) while fewer than MAXFLIGHT batches are in flight, builds batch/auto-<n> from origin/main, one squashed commit per PR, up to BATCHMAX PRs.
# Ready = open, branch w/<worker>/..., body starts "Worker:", not draft, no "hold" label, not in /data/landq/held.txt (PR numbers), not
# conflicting, not parked (parked until its head commit changes or, for a drop, until the doc is in approved.txt), not already in a batch/* PR.
# The batch body carries each member's body (so ACCEPT lines waive exactly as for a single PR); approved.txt is NOT pasted in: the gate reads it
# itself, and pasting every approved id would waive every approved doc in every batch (render-gate.sh: a waiver needs the id in approved.txt AND in
# the PR body or a commit message).
# Env: DRY=1 (print, change nothing), ONLY=N,N (only these PRs), BATCHMAX=8, MAXFLIGHT=3. Pause: touch /data/landq/batch-land/PAUSE.
# Log: /data/landq/batch-land.log. State: /data/landq/batch-land/{members,parked,split,retry,counter}.
R=${R:-starling-build/starling}; DRY=${DRY:-0}; ONLY=${ONLY:-}; BATCHMAX=${BATCHMAX:-8}; MAXFLIGHT=${MAXFLIGHT:-3}
LQ=/data/landq; S=$LQ/batch-land; LOG=$LQ/batch-land.log; CLONE=$S/clone
mkdir -p $S/members $S/parked $S/split $S/retry
log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$LOG"; }
run() { if [ "$DRY" = 1 ]; then log "DRY: $*"; return 0; fi; "$@"; }
exec 9>$S/lock; flock -n 9 || { echo "batch-land: another run is active"; exit 0; }
[ -e $S/PAUSE ] && { echo "batch-land: paused ($S/PAUSE)"; exit 0; }
AUTH="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$(gh auth token)" | base64 -w0)"
G() { GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraheader GIT_CONFIG_VALUE_0="$AUTH" git -C "$CLONE" "$@"; }
if [ ! -d "$CLONE/.git" ]; then mkdir -p "$CLONE"; git init -q "$CLONE"; git -C "$CLONE" remote add origin "https://github.com/$R.git"
  git -C "$CLONE" config user.name "batch-land"; git -C "$CLONE" config user.email "batch-land@starling.invalid"; fi
G fetch -q --no-tags origin main || { log "fetch main failed"; exit 1; }
PRS=$S/prs.json
gh pr list -R $R --state open -L 200 --json number,title,body,headRefName,headRefOid,labels,isDraft,createdAt,mergeable,isCrossRepository > $PRS || { log "gh pr list failed"; exit 1; }
pf() { jq -r --argjson n "$1" ".[]|select(.number==\$n)|$2" $PRS; }
all_approved() { for d in "$@"; do approved $d || return 1; done; }
approved() { grep -qE "^$1([ .]|$)" $LQ/approved.txt 2>/dev/null; }
comment() { run gh pr comment "$1" -R $R --body "$2" >/dev/null; }

# PRs inside any open batch/* PR (ours by state file; amd-10's by the #N in the body)
INBATCH=$S/inbatch.txt; : > $INBATCH
for f in $S/members/*.txt; do [ -e "$f" ] || continue; b=$(basename $f .txt)
  if [ -n "$(jq -r --arg b "batch/auto-$b" '.[]|select(.headRefName==$b)|.number' $PRS)" ]; then cut -d' ' -f1 $f >> $INBATCH; else rm -f $f; fi; done
jq -r '.[]|select((.headRefName|startswith("batch/")) and (.headRefName|startswith("batch/auto-")|not))|.body' $PRS | grep -oE '#[0-9]+' | tr -d '#' >> $INBATCH

# ---------- (A) batches in flight ----------
for f in $S/members/*.txt; do [ -e "$f" ] || continue; b=$(basename $f .txt); BR=batch/auto-$b
  bn=$(jq -r --arg b "$BR" '.[]|select(.headRefName==$b)|.number' $PRS)
  st=$(gh pr view $bn -R $R --json statusCheckRollup,mergeable -q '[(.statusCheckRollup[]?|select(.name=="render-gate")|.conclusion+"/"+.status), .mergeable]|join(" ")' 2>/dev/null)
  case "$st" in
   *SUCCESS*)
     if run gh pr merge $bn -R $R --rebase --delete-branch >/dev/null 2>&1; then log "batch #$bn ($BR) GREEN: merged"
       while read -r n sha; do comment $n "landed in batch #$bn"; run gh pr close $n -R $R >/dev/null; done < $f; rm -f $f
     else log "batch #$bn green but the merge failed ($(gh pr view $bn -R $R --json mergeable -q .mergeable)): closing it, members go back in line"
       run gh pr close $bn -R $R --delete-branch >/dev/null; rm -f $f; fi;;
   *FAILURE*|*CANCELLED*)
     rid=$(gh run list -R $R -w render-gate.yml -b $BR -L 1 --json databaseId -q '.[0].databaseId')
     gh run view $rid -R $R --log 2>/dev/null | grep -a 'BLOCKED\|BUILD FAILED\|timed out\|RAN OUT OF TIME\|no scores\|nothing was compared\|pair failed' | cut -c1-400 | head -40 > $S/fail-$b.txt
     if [ ! -e $S/retry/$b ] && grep -qaE 'timed out|RAN OUT OF TIME|no scores|nothing was compared|pair failed|BASE BUILD FAILED' $S/fail-$b.txt && ! grep -qa 'BLOCKED' $S/fail-$b.txt; then
       log "batch #$bn red from load/infrastructure ($(head -1 $S/fail-$b.txt | cut -c1-120)): rerun once"; touch $S/retry/$b; run gh run rerun $rid -R $R --failed >/dev/null; continue; fi
     # documents named by the block: v2 stems, Slides decks, Sheets books
     { sed -n 's/.*v2 drops not approved: *//p' $S/fail-$b.txt | tr ' ' '\n'; grep -aoE 'BLOCKED-(DECK|BOOK) +[^ ]+' $S/fail-$b.txt | awk '{print $2}'; } | grep -v '^$' | sort -u > $S/docs-$b.txt
     : > $S/named-$b.txt
     while read -r n sha; do G fetch -q --no-tags origin "pull/$n/head:refs/pr/$n" -f 2>/dev/null
       txt="$(pf $n .body)
$(G log --format=%B $(G merge-base origin/main refs/pr/$n 2>/dev/null)..refs/pr/$n 2>/dev/null)"
       hit=""; while read -r d; do [ -n "$d" ] || continue; grep -qF -- "$d" <<<"$txt" && hit="$hit $d"; done < $S/docs-$b.txt
       [ -n "$hit" ] && echo "$n$hit" >> $S/named-$b.txt; done < $f
     if [ -s $S/named-$b.txt ]; then log "batch #$bn RED, dropped docs map to PRs: $(tr '\n' ';' < $S/named-$b.txt)"
       while read -r n docs; do sha=$(pf $n .headRefOid); echo "$sha drop $docs" > $S/parked/$n
         comment $n "batch-land: batch #$bn went red on dropped document(s):$docs. This PR's body or commits name them, so it is taken out of the batch and parked until starling-bd approves the drop (the id in /data/landq/approved.txt) or you push a new head. The other PRs of the batch are resubmitted."; done < $S/named-$b.txt
     else
       m=$(wc -l < $f)
       if [ "$m" -le 1 ]; then n=$(cut -d' ' -f1 $f); sha=$(pf $n .headRefOid); echo "$sha red $(head -1 $S/fail-$b.txt | cut -c1-100)" > $S/parked/$n
         log "batch #$bn RED, single PR #$n, no named document: parked"; comment $n "batch-land: this PR alone went red in batch #$bn ($(head -1 $S/fail-$b.txt | cut -c1-200)). Parked until you push a new head."
       else h=$(( (m+1)/2 )); head -n $h $f > $S/split/$b-a.txt; tail -n +$((h+1)) $f > $S/split/$b-b.txt
         log "batch #$bn RED, no document named: split into $h + $((m-h)) PRs"; fi
     fi
     run gh pr close $bn -R $R --comment "red: see batch-land log" --delete-branch >/dev/null; rm -f $f $S/retry/$b;;
   *) : ;;  # pending
  esac
done

# ---------- (B) new batches ----------
inflight() { ls $S/members/*.txt 2>/dev/null | wc -l; }
held() { grep -qxE "$1( .*)?" $LQ/held.txt 2>/dev/null; }
ready() { n=$1; grep -qx $n $INBATCH && return 1; held $n && return 1
  [ -n "$ONLY" ] && ! echo ",$ONLY," | grep -q ",$n," && return 1
  p=$S/parked/$n; if [ -e $p ]; then read -r psha kind rest < $p
    if [ "$psha" != "$(pf $n .headRefOid)" ]; then rm -f $p
    elif [ "$kind" = drop ] && [ -n "$rest" ] && all_approved $rest; then rm -f $p   # every dropped doc is approved now
    else return 1; fi; fi
  return 0; }
mkdir -p $S/tmp; jq -r '.[]|select((.headRefName|test("^w/[^/]+/")) and (.body|startswith("Worker:")) and (.isDraft|not) and (.isCrossRepository|not) and (.mergeable!="CONFLICTING") and ((.labels|map(.name|ascii_downcase)|index("hold"))|not))|[.createdAt,.number]|@tsv' $PRS | sort | cut -f2 > $S/cand.txt
newbatch() { # args: PR numbers in order
  c=$(( $(cat $S/counter 2>/dev/null || echo 0) + 1 )); BR=batch/auto-$c; list=""; got=0
  G checkout -q -f --detach origin/main; G branch -q -D tmp-batch 2>/dev/null; G checkout -q -b tmp-batch origin/main
  : > $S/members/$c.new
  for n in "$@"; do [ $got -ge $BATCHMAX ] && break
    G fetch -q --no-tags origin "pull/$n/head:refs/pr/$n" -f || { log "fetch of #$n failed"; continue; }
    # alone on main first: a clash here is the author's to fix; a clash only with an earlier member waits for the next batch
    G checkout -q -f --detach origin/main; if ! G merge --squash -q refs/pr/$n >/dev/null 2>&1; then G reset -q --hard; G merge --abort 2>/dev/null
      log "#$n does not apply to main: skipped, asked the author to rebase"; comment $n "batch-land: this PR does not apply cleanly to origin/main. Please rebase onto origin/main and push; it is picked up again automatically."; continue; fi
    G reset -q --hard; G checkout -q -f tmp-batch
    if ! G merge --squash -q refs/pr/$n >/dev/null 2>&1; then G reset -q --hard; log "#$n clashes with an earlier member: next batch"; continue; fi
    if G diff --cached --quiet; then log "#$n changes nothing on top of main: skipped"; G reset -q --hard; continue; fi
    base=$(G merge-base origin/main refs/pr/$n); au=$(G log -1 --format='%an <%ae>' refs/pr/$n)
    { echo "$(pf $n .title) (#$n)"; echo; G log --format=%B --reverse $base..refs/pr/$n; echo "Batched by batch-land"; } > $S/msg.txt
    G commit -q --author="$au" -F $S/msg.txt && { got=$((got+1)); list="$list $n"; echo "$n $(pf $n .headRefOid)" >> $S/members/$c.new; }
  done
  if [ $got -eq 0 ]; then rm -f $S/members/$c.new; return 1; fi
  { echo "Batch of $got PR(s) landed by batch-land (no model): $(for n in $list; do printf '#%s ' $n; done)"; echo
    for n in $list; do grep -hE '^ACCEPT:' <<<"$(pf $n .body)"; done | sort -u; echo
    for n in $list; do echo "## #$n $(pf $n .title)"; pf $n .body | grep -v 'Generated with \[Claude Code\]'; echo; done; } > $S/body.txt
  if [ "$DRY" = 1 ]; then log "DRY: would push $BR with$list"; rm -f $S/members/$c.new; return 0; fi
  G push -q -f origin tmp-batch:refs/heads/$BR || { log "push of $BR failed"; rm -f $S/members/$c.new; return 1; }
  url=$(gh pr create -R $R --base main --head $BR --title "Batch $c: $(for n in $list; do printf '#%s ' $n; done)" --body-file $S/body.txt) || { log "batch PR create failed"; rm -f $S/members/$c.new; return 1; }
  echo $c > $S/counter; mv $S/members/$c.new $S/members/$c.txt
  for n in $list; do echo $n >> $INBATCH; done
  log "opened $url ($BR) with$list"; return 0; }

# split halves first, then the oldest ready PRs
while [ "$(inflight)" -lt "$MAXFLIGHT" ]; do
  sp=$(ls $S/split/*.txt 2>/dev/null | head -1)
  if [ -n "$sp" ]; then L=$(cut -d' ' -f1 $sp | while read -r n; do pf $n .number | grep -q . && ready $n && echo $n; done); rm -f $sp
  else L=$(while read -r n; do ready $n && echo $n; done < $S/cand.txt | head -$((BATCHMAX*2))); fi
  [ -n "$L" ] || { log "nothing ready"; break; }
  newbatch $L || break
  [ "$DRY" = 1 ] && break
done
G checkout -q -f --detach origin/main 2>/dev/null
exit 0
