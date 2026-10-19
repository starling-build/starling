#!/usr/bin/env bash
# The built site in a browser (docs/plans/site.md): examples/site built
# into a folder, that folder served as GitHub Pages would serve it, and
# headless Chrome opening a page by its URL, reading it, moving to another
# page from the tree (the address bar following), and searching. Also the
# same site under a project base (/demo/).
#
#   test/site-web.sh        needs apps/OfficeApp/.build/debug/OfficeApp, the
#                           web stage, node and Chrome
#   SITE_PORT, OUT          defaults below; screenshots in OUT
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="${OFFICE_APP:-$REPO/apps/OfficeApp/.build/debug/OfficeApp}"
STAGE="${STAGE:-$REPO/.stage-web-OfficeApp}"
OUT="${OUT:-${TMPDIR:-/tmp}/site-web}"
SERVE_PORT="${SITE_PORT:-18092}"
URL="http://127.0.0.1:$SERVE_PORT"
fails=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 — got '$2', wanted '$3'"; fi; }
evals() { grep '^eval: ' "$1" | sed 's/^eval: //'; }
# (bash 3 on macOS has no mapfile: the eval lines are read in a loop.)

[ -x "$APP" ] || { echo "no OfficeApp at $APP" >&2; exit 2; }
[ -f "$STAGE/app.wasm" ] || { echo "no web stage at $STAGE" >&2; exit 2; }
command -v node >/dev/null || { echo "no node" >&2; exit 2; }

rm -rf "$OUT"; mkdir -p "$OUT"
cp -R "$REPO/examples/site" "$OUT/repo"
# A user site at the root, and the same site as a project site under /demo/.
"$APP" --site-build "$OUT/repo" --out "$OUT/www" --web "$STAGE" > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 2; }
"$APP" --site-build "$OUT/repo" --out "$OUT/www/demo" --web "$STAGE" --base /demo/ > "$OUT/build2.log" 2>&1 || { cat "$OUT/build2.log"; exit 2; }

cleanup() { [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null; }
trap cleanup EXIT
python3 "$REPO/build/tools/web-serve.py" "$OUT/www" "$SERVE_PORT" > "$OUT/serve.log" 2>&1 &
PID=$!
for _ in $(seq 1 50); do curl -s -o /dev/null "$URL/manifest.json" && break; sleep 0.1; done

echo "── served as Pages would"
check "a page's shell is served at its route" "$(curl -s -o /dev/null -w '%{http_code}' "$URL/publishing/")" 200
check "the shell carries the page's title" "$(curl -s "$URL/publishing/" | grep -o 'og:title" content="[^"]*"')" 'og:title" content="Publishing"'
check "the manifest is served" "$(curl -s "$URL/manifest.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["home"])')" index

echo "── headless Chrome: open by URL, read, move, search"
DRIVE=(node "$REPO/build/tools/web-drive.mjs")
export PORT="${DEVTOOLS:-9347}" CHROME_PROFILE="$OUT/chrome-profile" W=1400 H=900
rm -rf "$CHROME_PROFILE"
# The tree is in the sidebar: Welcome, Getting started, Publishing, About,
# 27px a row from y≈285; the search field sits above it at y≈233, and
# its hits take the tree's place.
URL="$URL/publishing/" "${DRIVE[@]}" wait 9000 shot "$OUT/1-publishing.png" \
    eval "document.title" eval "starling.debug('slug')" eval "starling.debug('text').slice(0, 40)" \
    click 100 366 wait 1500 shot "$OUT/2-about.png" \
    eval "location.pathname" eval "starling.debug('slug')" \
    click 140 233 wait 300 type "slug" wait 1200 shot "$OUT/3-search.png" \
    click 100 295 wait 1500 eval "starling.debug('slug')" eval "location.pathname" \
    > "$OUT/drive.log" 2>&1
tail -3 "$OUT/drive.log" | sed 's/^/        /'
R=(); while IFS= read -r l; do R+=("$l"); done < <(evals "$OUT/drive.log")
check "the tab is titled after the page and site" "${R[0]:-}" '"Publishing — Starling Site"'
check "the app opened the page the URL names" "${R[1]:-}" '"publishing"'
check "the page's text is drawn" "${R[2]:-}" '"Publishing\nPublish builds the site into "'
check "a tree click moves the address bar" "${R[3]:-}" '"/about/"'
check "and opens that page" "${R[4]:-}" '"about"'
check "a search hit opens its page" "${R[5]:-}" '"getting-started"'
check "at its route" "${R[6]:-}" '"/getting-started/"'

echo "── the same site under /demo/"
URL="$URL/demo/about/" "${DRIVE[@]}" wait 9000 shot "$OUT/4-demo.png" \
    eval "starling.debug('slug')" click 100 339 wait 1500 eval "location.pathname" eval "starling.debug('slug')" \
    > "$OUT/drive2.log" 2>&1
D=(); while IFS= read -r l; do D+=("$l"); done < <(evals "$OUT/drive2.log")
check "a project site opens the page under its base" "${D[0]:-}" '"about"'
check "and moves within the base" "${D[1]:-}" '"/demo/publishing/"'
check "to the page clicked" "${D[2]:-}" '"publishing"'

echo
if [ $fails -eq 0 ]; then echo "site-web: all passed"; else echo "site-web: $fails failed"; fi
[ $fails -eq 0 ]
