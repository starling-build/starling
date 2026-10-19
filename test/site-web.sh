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
# The site names its repository, so the reader shows History.
python3 - "$OUT/repo/site.json" <<'PYX'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['repository']='https://github.com/example/site'; json.dump(d, open(p,'w'), indent=2)
PYX
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
    eval "document.querySelector('#starling-text h1')?.textContent" \
    click 140 233 wait 300 type "slug" wait 1200 shot "$OUT/3-search.png" \
    click 100 295 wait 1500 eval "starling.debug('slug')" eval "location.pathname" \
    > "$OUT/drive.log" 2>&1
tail -3 "$OUT/drive.log" | sed 's/^/        /'
R=(); while IFS= read -r l; do R+=("$l"); done < <(evals "$OUT/drive.log")
check "the tab is titled after the page and site" "${R[0]:-}" '"Publishing — Starling Site"'
check "the app opened the page the URL names" "${R[1]:-}" '"publishing"'
check "the page's text is drawn" "${R[2]:-}" '"Publishing\nPublish builds the site into "'
check "a tree click moves the address bar" "${R[3]:-}" '"/about/"'
check "and the text layer for screen readers follows" "$(grep -c 'eval: "About"' "$OUT/drive.log")" 1
check "and opens that page" "${R[4]:-}" '"about"'
check "a search hit opens its page" "${R[6]:-}" '"getting-started"'
check "at its route" "${R[7]:-}" '"/getting-started/"'

echo "── a paged page: pages on a desktop, flow on a phone, contents with page numbers, a link to a paragraph"
# sample-paper came from a .docx and carries its page setup; 1403114754 is
# the id of its "Cryptographic Module Specification" heading.
URL="$URL/sample-paper/#p=1403114754" "${DRIVE[@]}" wait 12000 shot "$OUT/5-paged.png" \
    eval "starling.debug('view')" eval "+starling.debug('pages') > 3" \
    eval "starling.debug('toc').split('\n').filter(l => /^\d\t[1-9]\d*\t/.test(l)).length > 5" \
    eval "starling.debug('toc').split('\n').find(l => l.includes('Cryptographic Module Specification'))" \
    eval "starling.debug('caret')" \
    > "$OUT/drive3.log" 2>&1
P=(); while IFS= read -r l; do P+=("$l"); done < <(evals "$OUT/drive3.log")
check "a page with a page setup opens as pages on a desktop" "${P[0]:-}" '"pages"'
check "and has more than three of them" "${P[1]:-}" true
check "the contents carry page numbers" "${P[2]:-}" true
check "a heading's entry names its page" "$(printf '%s' "${P[3]:-}" | grep -c '^"1\\t[0-9]*\\tCryptographic Module Specification"$')" 1
check "the route's #p= opened at that paragraph" "${P[4]:-}" '"1403114754"'
W=800 H=900 URL="$URL/sample-paper/" "${DRIVE[@]}" wait 12000 eval "starling.debug('view')" > "$OUT/drive4.log" 2>&1
check "the same page is flow on a narrow screen" "$(evals "$OUT/drive4.log" | head -1)" '"flow"'
export W=1400 H=900
# A finger on the document scrolls it (a phone): three drags up, and the
# status bar's page has moved on.
URL="$URL/sample-paper/" "${DRIVE[@]}" wait 12000 eval "starling.debug('page')" \
    touchdrag 700 750 0 -500 touchdrag 700 750 0 -500 touchdrag 700 750 0 -500 wait 1500 \
    eval "+starling.debug('page') >= 2" > "$OUT/drive6.log" 2>&1
T=(); while IFS= read -r l; do T+=("$l"); done < <(evals "$OUT/drive6.log")
check "a page opens at its first page" "${T[0]:-}" '"1"'
check "a finger drag scrolls the document" "${T[1]:-}" true
# Find: the Find button opens a field after PDF; typing selects the first
# match. Copy: a double-click selects a word, Ctrl+C puts it on the system
# clipboard (stubbed here: the page's writeText records what it was given).
# The header, left to right: Pages, Flow, Contents, Link to paragraph, PDF,
# Word (x≈814), History (x≈893, since the site names its repository), Find
# (x≈969). History opens a new tab (stubbed: window.open records the URL).
STUB="navigator.clipboard.writeText = (t) => { window.__copied = t; return Promise.resolve(); }; window.open = (u) => { window.__opened = u; return null; }; 'stubbed'"
rm -rf "$OUT/downloads2"; mkdir -p "$OUT/downloads2"
URL="$URL/sample-paper/" "${DRIVE[@]}" downloads "$OUT/downloads2" wait 12000 eval "$STUB" \
    dblclick 843 597 wait 500 eval "starling.debug('selection')" chord ctrl c wait 500 eval "window.__copied" \
    click 893 220 wait 500 eval "window.__opened" \
    click 814 220 wait 4000 eval "starling.debug('status')" \
    click 969 220 wait 500 type "Cryptographic Boundary" wait 800 eval "starling.debug('selection')" \
    > "$OUT/drive7.log" 2>&1
F=(); while IFS= read -r l; do F+=("$l"); done < <(evals "$OUT/drive7.log")
check "a double-click selects a word" "${F[1]:-}" '"BoringCrypto"'
check "Ctrl+C puts the selection on the clipboard" "${F[2]:-}" '"BoringCrypto"'
check "History opens the page's commits on GitHub" "${F[3]:-}" '"https://github.com/example/site/commits/main/pages/sample-paper.json"'
check "Word says it exported" "${F[4]:-}" '"Exported sample-paper.docx"'
check "and the .docx landed" "$(ls "$OUT/downloads2" 2>/dev/null | grep -c '^sample-paper.docx$')" 1
check "find selects the first match of what is typed, case aside" "${F[5]:-}" '"cryptographic boundary"'
# The PDF button, with the download landing in OUT; the Contents panel's
# first entry, clicked, moves the caret to the first heading.
rm -rf "$OUT/downloads"; mkdir -p "$OUT/downloads"
URL="$URL/sample-paper/" "${DRIVE[@]}" downloads "$OUT/downloads" wait 12000 \
    click 520 220 wait 1500 click 1250 300 wait 1500 eval "starling.debug('caret')" shot "$OUT/6-contents.png" \
    click 780 220 wait 30000 eval "starling.debug('status')" > "$OUT/drive5.log" 2>&1
C=(); while IFS= read -r l; do C+=("$l"); done < <(evals "$OUT/drive5.log")
check "a contents entry moves the caret to its heading" "$(printf '%s' "${C[0]:-}" | grep -Ec '^"[1-9][0-9]*"$')" 1
check "the PDF button says it exported" "${C[1]:-}" '"Exported sample-paper.pdf"'
check "and the PDF is the same painter's pages" "$(ls "$OUT/downloads" 2>/dev/null | grep -c '^sample-paper.pdf$')" 1

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
