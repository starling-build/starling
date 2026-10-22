#!/usr/bin/env bash
# The wiki in a browser (docs/plans/wiki.md W1): the server serving the
# wasm build, headless Chrome signing in, opening a page by its URL,
# editing it and saving, then the API confirming the new version. Also the
# shell page's meta tags as a link unfurler would read them.
#
#   test/wiki-web.sh                    needs build/web-app.sh OfficeApp
#                                       --package apps/OfficeApp (the stage)
#                                       and a local Postgres
#   WIKI_DB, WIKI_PORT, STAGE, OUT       defaults below; screenshots in OUT
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DB="${WIKI_DB:-starling_wiki_web}"
PORT="${WIKI_PORT:-18081}"
STAGE="${STAGE:-$REPO/.stage-web-OfficeApp}"
OUT="${OUT:-${TMPDIR:-/tmp}/wiki-web}"
SERVER="$REPO/wiki/.build/debug/wiki-server"
APP="${OFFICE_APP:-$REPO/apps/OfficeApp/.build/debug/OfficeApp}"
SERVE_PORT="$PORT"  # PORT is the DevTools port once web-drive is set up below
URL="http://127.0.0.1:$PORT"
mkdir -p "$OUT"
fails=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 — got '$2', wanted '$3'"; fi; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval('d'+sys.argv[1]))" "$1" 2>/dev/null; }

[ -x "$SERVER" ] || { echo "no wiki-server (cd wiki && swift build)" >&2; exit 2; }
[ -f "$STAGE/index.html" ] && [ -f "$STAGE/app.wasm" ] || { echo "no web stage at $STAGE (build/web-app.sh OfficeApp --package apps/OfficeApp)" >&2; exit 2; }
command -v node >/dev/null || { echo "no node" >&2; exit 2; }

cleanup() { [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null; }
trap cleanup EXIT
export WIKI_DATABASE_URL="postgres://localhost/$DB"
dropdb --if-exists "$DB" 2>/dev/null; createdb "$DB" || exit 2
"$SERVER" migrate >/dev/null 2>&1
"$SERVER" add-user alice --name Alice --password pw1 --admin >/dev/null
"$SERVER" create-space DOCS --name "Documentation" >/dev/null
"$SERVER" serve --port "$SERVE_PORT" --web-root "$STAGE" --office-app "$APP" --public-url "$URL" > "$OUT/server.log" 2>&1 &
PID=$!
for _ in $(seq 1 50); do curl -s -o /dev/null "$URL/api/v1/me" && break; sleep 0.1; done

JAR="$OUT/alice.jar"
curl -s -c "$JAR" -H 'content-type: application/json' -d '{"login":"alice","password":"pw1"}' "$URL/api/v1/login" >/dev/null
HOME_ID="$(curl -s -b "$JAR" "$URL/api/v1/spaces/DOCS" | json '["homePage"]')"
PAGE="$(curl -s -b "$JAR" -H 'content-type: application/json' -d "{\"title\":\"Getting Started\",\"parent\":\"$HOME_ID\"}" "$URL/api/v1/spaces/DOCS/pages")"
PID1="$(echo "$PAGE" | json '["id"]')"
ROUTE="/s/DOCS/p/$PID1/getting-started"

echo "── the shell"
HTML="$(curl -s "$URL$ROUTE")"
check "og:title is the page title" "$(echo "$HTML" | grep -o 'og:title" content="[^"]*"' | head -1)" 'og:title" content="Getting Started"'
check "the app's files are served" "$(curl -s -o /dev/null -w '%{http_code}' "$URL/starling.js")" 200
check "the module is served" "$(curl -s -o /dev/null -w '%{http_code}' -r 0-10 "$URL/app.wasm")" 206

echo "── headless Chrome: sign in, open, edit, save"
DRIVE=(node "$REPO/build/tools/web-drive.mjs")
export PORT="${DEVTOOLS:-9345}" CHROME_PROFILE="$OUT/chrome-profile" W=1400 H=900
rm -rf "$CHROME_PROFILE"
# The sign-in card is centred: login field, password field, button; then
# the Edit button, which opens the whole Writer on the page (title bar,
# ribbon, document); a click into the document, Ctrl+S (Writer's Save,
# which the wiki stores as a version), and "Back to wiki" in the title bar.
# The password is typed the way a phone's keyboard or an input method
# types: as composed text into the page's hidden field, not as keys.
COMPOSE="document.getElementById('starling-ime').dispatchEvent(new InputEvent('beforeinput', {inputType: 'insertText', data: 'pw1', cancelable: true, bubbles: true}))"
URL="$URL$ROUTE" "${DRIVE[@]}" wait 9000 shot "$OUT/1-signin.png" \
    click 700 500 wait 300 eval "document.activeElement.id" type alice \
    click 700 560 wait 300 eval "$COMPOSE" wait 200 press Enter \
    wait 4000 shot "$OUT/2-page.png" \
    click 750 220 wait 3000 shot "$OUT/3-writer.png" \
    click 700 450 wait 300 type "Hello from the browser. " wait 500 \
    chord ctrl s wait 3000 shot "$OUT/4-saved.png" \
    click 64 26 wait 2500 shot "$OUT/5-back.png" \
    > "$OUT/drive.log" 2>&1
tail -3 "$OUT/drive.log" | sed 's/^/        /'
[ -s "$OUT/2-page.png" ] && pass "screenshots taken ($OUT)" || fail "no screenshots — see $OUT/drive.log"
check "a focused field focuses the page's hidden text field (a phone's keyboard)" "$(grep -c 'eval: "starling-ime"' "$OUT/drive.log")" 1

AFTER="$(curl -s -b "$JAR" "$URL/api/v1/pages/$PID1")"
check "the browser's save made version 2" "$(echo "$AFTER" | json '["version"]')" 2 || echo "        page: $(echo "$AFTER" | /usr/bin/cut -c1-200)"
check "the typed text reached the server" "$(echo "$AFTER" | json '["plainText"]' | grep -c 'Hello from the browser')" 1
check "the lock was released on Back to wiki" "$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" "$URL/api/v1/pages/$PID1/lock")" 404

echo "── serve --dev-user"
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
"$SERVER" serve --port "$SERVE_PORT" --web-root "$STAGE" --office-app "$APP" --public-url "$URL" --dev-user alice > "$OUT/server-dev.log" 2>&1 &
PID=$!
for _ in $(seq 1 50); do curl -s -o /dev/null "$URL/api/v1/me" && break; sleep 0.1; done
check "no cookie, and the visitor is the dev user" "$(curl -s "$URL/api/v1/me" | json '["login"]')" alice

echo
if [ $fails -eq 0 ]; then echo "wiki-web: all passed"; else echo "wiki-web: $fails failed"; fi
[ $fails -eq 0 ]
