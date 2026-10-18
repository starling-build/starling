#!/usr/bin/env bash
# The wiki server, driven end to end (docs/plans/wiki.md W1): a fresh
# database, the migrations, a user and a space, then every API the client
# uses — sign-in, tree, create, save with the base-version check, locks,
# import of a .docx through the headless OfficeApp, export back to .docx,
# and the shell page's meta tags.
#
#   test/wiki-api.sh              needs a local Postgres (createdb works)
#   WIKI_DB=<name>                default starling_wiki_test (dropped and recreated)
#   WIKI_PORT=<port>              default 18080
#   OFFICE_APP=<binary>           default apps/OfficeApp/.build/debug/OfficeApp
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DB="${WIKI_DB:-starling_wiki_test}"
PORT="${WIKI_PORT:-18080}"
APP="${OFFICE_APP:-$REPO/apps/OfficeApp/.build/debug/OfficeApp}"
SERVER="$REPO/wiki/.build/debug/wiki-server"
URL="http://127.0.0.1:$PORT"
TMP="$(mktemp -d)"
fails=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 — got '$2', wanted '$3'"; fi; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval('d'+sys.argv[1]))" "$1" 2>/dev/null; }

[ -x "$SERVER" ] || { echo "no wiki-server at $SERVER (cd wiki && swift build)" >&2; exit 2; }
command -v createdb >/dev/null || { echo "no Postgres client tools" >&2; exit 2; }

cleanup() { [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

export WIKI_DATABASE_URL="postgres://localhost/$DB"
dropdb --if-exists "$DB" 2>/dev/null
createdb "$DB" || { echo "createdb $DB failed" >&2; exit 2; }
"$SERVER" migrate >/dev/null 2>&1 || { echo "migrate failed" >&2; exit 1; }
"$SERVER" add-user alice --name Alice --password pw1 --admin >/dev/null
"$SERVER" add-user bob --name Bob --password pw2 >/dev/null
"$SERVER" create-space ENG --name Engineering >/dev/null
"$SERVER" serve --port "$PORT" --web-root "$TMP" --office-app "$APP" --public-url "$URL" > "$TMP/server.log" 2>&1 &
PID=$!
for _ in $(seq 1 50); do curl -s -o /dev/null "$URL/api/v1/me" && break; sleep 0.1; done

A="$TMP/alice.jar"; B="$TMP/bob.jar"
a() { curl -s -b "$A" -c "$A" "$@"; }
b() { curl -s -b "$B" -c "$B" "$@"; }
code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }

echo "── sign-in"
check "anonymous is 401" "$(code "$URL/api/v1/me")" 401
check "wrong password is 401" "$(code -X POST -H 'content-type: application/json' -d '{"login":"alice","password":"no"}' "$URL/api/v1/login")" 401
a -X POST -H 'content-type: application/json' -d '{"login":"alice","password":"pw1"}' "$URL/api/v1/login" >/dev/null
b -X POST -H 'content-type: application/json' -d '{"login":"bob","password":"pw2"}' "$URL/api/v1/login" >/dev/null
check "me after login" "$(a "$URL/api/v1/me" | json '["login"]')" alice

echo "── spaces and pages"
check "spaces lists ENG" "$(a "$URL/api/v1/spaces" | json '[0]["key"]')" ENG
HOME_ID="$(a "$URL/api/v1/spaces/ENG" | json '["homePage"]')"
check "tree has the home page" "$(a "$URL/api/v1/spaces/ENG/tree" | json '[0]["id"]')" "$HOME_ID"
PAGE="$(a -X POST -H 'content-type: application/json' -d "{\"title\":\"Hello World\",\"parent\":\"$HOME_ID\"}" "$URL/api/v1/spaces/ENG/pages")"
PID1="$(echo "$PAGE" | json '["id"]')"
check "new page is version 1" "$(echo "$PAGE" | json '["version"]')" 1
check "new page slug" "$(echo "$PAGE" | json '["slug"]')" hello-world
check "tree has two pages" "$(a "$URL/api/v1/spaces/ENG/tree" | json '.__len__()')" 2
BODY='{"schema":1,"document":{"paragraphs":[{"text":"First line","runs":[{"length":10,"style":{}}],"style":{}}]}}'
SAVED="$(a -X PUT -H 'content-type: application/json' -d "{\"title\":\"Hello World\",\"body\":$(python3 -c "import json;print(json.dumps('$BODY'))"),\"base\":1}" "$URL/api/v1/pages/$PID1")"
check "save makes version 2" "$(echo "$SAVED" | json '["version"]')" 2
check "plain text derived from the body" "$(echo "$SAVED" | json '["plainText"]')" "First line"
check "a stale base is 409" "$(code -b "$A" -X PUT -H 'content-type: application/json' -d "{\"title\":\"x\",\"body\":\"{}\",\"base\":1}" "$URL/api/v1/pages/$PID1")" 409
check "version 1 still readable" "$(a "$URL/api/v1/pages/$PID1?version=1" | json '["version"]')" 1
check "two versions listed" "$(a "$URL/api/v1/pages/$PID1/versions" | json '.__len__()')" 2

echo "── locks"
LOCK="$(a -X POST -H 'content-type: application/json' -d '{}' "$URL/api/v1/pages/$PID1/lock")"
TOKEN="$(echo "$LOCK" | json '["token"]')"
check "alice holds the lock" "$(echo "$LOCK" | json '["userName"]')" Alice
check "bob cannot take it" "$(code -b "$B" -X POST -H 'content-type: application/json' -d '{}' "$URL/api/v1/pages/$PID1/lock")" 423
check "bob cannot save over it" "$(code -b "$B" -X PUT -H 'content-type: application/json' -d "{\"title\":\"x\",\"body\":\"{}\",\"base\":2}" "$URL/api/v1/pages/$PID1")" 423
check "alice renews with her token" "$(a -X POST -H 'content-type: application/json' -d "{\"token\":\"$TOKEN\"}" "$URL/api/v1/pages/$PID1/lock" | json '["token"]')" "$TOKEN"
check "alice saves with her token" "$(a -X PUT -H 'content-type: application/json' -d "{\"title\":\"Hello World\",\"body\":\"{}\",\"base\":2,\"lockToken\":\"$TOKEN\"}" "$URL/api/v1/pages/$PID1" | json '["version"]')" 3
a -X DELETE "$URL/api/v1/pages/$PID1/lock?token=$TOKEN" >/dev/null
check "released lock is gone" "$(code -b "$A" "$URL/api/v1/pages/$PID1/lock")" 404
check "bob can lock now" "$(code -b "$B" -X POST -H 'content-type: application/json' -d '{}' "$URL/api/v1/pages/$PID1/lock")" 200

echo "── import and export through OfficeApp"
DOCX="$REPO/test/corpus/docx/docs/checkboxes.docx"
if [ -x "$APP" ] && [ -f "$DOCX" ]; then
    IMP="$(a -X POST --data-binary "@$DOCX" "$URL/api/v1/spaces/ENG/import?name=checkboxes.docx&parent=$HOME_ID")"
    PID2="$(echo "$IMP" | json '["id"]')"
    check "imported page titled by its file" "$(echo "$IMP" | json '["title"]')" checkboxes
    check "imported body has paragraphs" "$(a "$URL/api/v1/pages/$PID2" | python3 -c 'import json,sys; d=json.load(sys.stdin); b=json.loads(d["body"]); print(len(b["document"]["paragraphs"])>0)')" True
    check "imported text is searchable text" "$(echo "$IMP" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["plainText"])>0)')" True
    a -o "$TMP/out.docx" "$URL/api/v1/pages/$PID2/export.docx"
    check "export is a zip" "$(head -c 2 "$TMP/out.docx")" PK
    check "export reads back" "$("$APP" --page-roundtrip "$TMP/out.docx" | cut -d' ' -f1)" OK
else
    echo "  skip  no OfficeApp or corpus"
fi

echo "── search"
check "a word in the body is found" "$(a "$URL/api/v1/search?q=first" | json '[0]["id"]')" "$PID1"
check "a title word is found" "$(a "$URL/api/v1/search?q=hello" | json '[0]["title"]')" "Hello World"
check "nothing matches nonsense" "$(a "$URL/api/v1/search?q=zzqqxx" | json '.__len__()')" 0
check "scoped to another space finds nothing" "$(a "$URL/api/v1/search?q=first&space=NOPE" | json '.__len__()')" 0
ZH="$(a -X POST -H 'content-type: application/json' -d "{\"title\":\"管理办法\",\"parent\":\"$HOME_ID\",\"body\":\"{}\",\"plainText\":\"第一条 为贯彻落实统筹整合使用财政涉农资金\"}" "$URL/api/v1/spaces/ENG/pages" | json '["id"]')"
check "a Chinese substring is found" "$(a "$URL/api/v1/search?q=%E8%B4%A2%E6%94%BF%E6%B6%89%E5%86%9C" | json '[0]["id"]')" "$ZH"

echo "── the shell"
HTML="$(curl -s "$URL/s/ENG/p/$PID1/hello-world")"
check "shell carries og:title" "$(echo "$HTML" | grep -o 'og:title" content="[^"]*"' | head -1)" 'og:title" content="Hello World"'
check "shell carries the route" "$(echo "$HTML" | grep -o 'starling-route" content="[^"]*"' | head -1)" "starling-route\" content=\"/s/ENG/p/$PID1/hello-world\""
check "shell is html" "$(code "$URL/s/ENG")" 200

echo "── delete and move"
check "move under home" "$(code -b "$A" -X POST -H 'content-type: application/json' -d "{\"parent\":\"$HOME_ID\",\"position\":5}" "$URL/api/v1/pages/$PID1/move")" 200
check "move under itself refused" "$(code -b "$A" -X POST -H 'content-type: application/json' -d "{\"parent\":\"$PID1\",\"position\":0}" "$URL/api/v1/pages/$PID1/move")" 400
a -X DELETE "$URL/api/v1/pages/$PID1" >/dev/null
check "deleted page is 404" "$(code -b "$A" "$URL/api/v1/pages/$PID1")" 404

echo
if [ $fails -eq 0 ]; then echo "wiki-api: all passed"; else echo "wiki-api: $fails failed"; sed -n 1,40p "$TMP/server.log" | grep -i "error\|warn" | head; fi
[ $fails -eq 0 ]
