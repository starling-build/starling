#!/usr/bin/env bash
# A site from a repository (docs/plans/site.md): `OfficeApp --site-build`
# on a copy of examples/site, then what GitHub Pages would serve checked
# file by file — the app, the pages, the manifest and search index, a
# shell page per route with its meta tags, the home and 404 pages, and a
# project-site base. Then a page edited the way the native app's Save
# writes it, rebuilt, and the shell page following.
#
#   test/site-build.sh      needs apps/OfficeApp/.build/debug/OfficeApp and
#                           the web stage (build/web-app.sh OfficeApp
#                           --package apps/OfficeApp)
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="${OFFICE_APP:-$REPO/apps/OfficeApp/.build/debug/OfficeApp}"
STAGE="${STAGE:-$REPO/.stage-web-OfficeApp}"
OUT="${OUT:-${TMPDIR:-/tmp}/site-build}"
fails=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 — got '$2', wanted '$3'"; fi; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval('d'+sys.argv[1]))" "$1" 2>/dev/null; }

[ -x "$APP" ] || { echo "no OfficeApp at $APP" >&2; exit 2; }
[ -f "$STAGE/index.html" ] && [ -f "$STAGE/app.wasm" ] || { echo "no web stage at $STAGE" >&2; exit 2; }

rm -rf "$OUT"; mkdir -p "$OUT"
SITE="$OUT/repo"
cp -R "$REPO/examples/site" "$SITE"

echo "── build"
"$APP" --site-build "$SITE" --web "$STAGE" > "$OUT/build.log" 2>&1
check "site-build exits 0" "$?" 0
sed 's/^/        /' "$OUT/build.log"
DIST="$SITE/docs"
for f in app.wasm starling.js skwasm/skwasm.js manifest.json search.json index.html 404.html .nojekyll pages/index.json pages/publishing.json getting-started/index.html publishing/index.html about/index.html; do
    [ -f "$DIST/$f" ] && pass "docs/$f" || fail "docs/$f missing"
done
[ -f "$DIST/fonts/manifest.json" ] && pass "docs/fonts/" || fail "docs/fonts/ missing"
check "the manifest lists every page" "$(json '["pages"][1]["children"][0]["slug"]' < "$DIST/manifest.json")" publishing
check "the manifest's home is the first page" "$(json '["home"]' < "$DIST/manifest.json")" index
check "the search index has the pages' text" "$(json '[2]["text"][:10]' < "$DIST/search.json")" "Publishing"
check "a page from a .docx keeps its page setup" "$(json '["pageSetup"]["width"]' < "$DIST/pages/sample-paper.json")" 612
check "a page from text has none" "$(grep -c '"pageSetup"' "$DIST/pages/index.json")" 0
check "a site with no Chinese text ships no Chinese font" "$(ls "$DIST/fonts" | grep -c NotoSansSC)" 0
check "nor lists it" "$(grep -c NotoSansSC "$DIST/fonts/manifest.json")" 0
check "a shell page names its page" "$(grep -o 'og:title" content="[^"]*"' "$DIST/publishing/index.html")" 'og:title" content="Publishing"'
check "a shell page summarises its page" "$(grep -c 'og:description" content="Publishing Publish builds the site' "$DIST/publishing/index.html")" 1
check "a shell page's title carries the site's" "$(grep -o '<title>[^<]*</title>' "$DIST/publishing/index.html")" '<title>Publishing — Starling Site</title>'
check "a shell page starts the app in site mode" "$(grep -c "args: \['--site', '/'\]" "$DIST/publishing/index.html")" 1
check "a shell page resolves assets at the base" "$(grep -c '<base href="/">' "$DIST/about/index.html")" 1
check "the page's text layer is hidden HTML with headings" "$(grep -c '<article id="starling-article" aria-label="About">' "$DIST/about/index.html")" 1
check "a heading is a heading there" "$(grep -c '^<h1>About</h1>$' "$DIST/about/index.html")" 1
check "the site's pages are real links in it" "$(grep -c '<li>&nbsp;&nbsp;<a href="/publishing/">Publishing</a></li>' "$DIST/about/index.html")" 1
check "and so are the page's downloads" "$(grep -c '<a href="/about/about.pdf">Download as PDF</a> · <a href="/about/about.docx">Download as Word</a>' "$DIST/about/index.html")" 1
check "the build wrote the page as a PDF" "$(head -c 4 "$DIST/sample-paper/sample-paper.pdf" 2>/dev/null)" '%PDF'
check "and as Word" "$(unzip -l "$DIST/sample-paper/sample-paper.docx" 2>/dev/null | grep -c 'word/document.xml')" 1
check "the manifest says so" "$(json '["exports"]' < "$DIST/manifest.json")" True
check "a paragraph is a paragraph" "$(grep -c '^<p>Pages are stored as the document model' "$DIST/about/index.html")" 1
check "the home shell page is the first page's" "$(grep -o 'og:title" content="[^"]*"' "$DIST/index.html")" 'og:title" content="Welcome"'
check "404 loads the app" "$(grep -c "args: \['--site'" "$DIST/404.html")" 1

echo "── rebuild into the same folder"
"$APP" --site-build "$SITE" --web "$STAGE" > "$OUT/build2.log" 2>&1
check "a second build over the first exits 0" "$?" 0
mkdir -p "$OUT/stranger" && echo x > "$OUT/stranger/notes.txt"
"$APP" --site-build "$SITE" --out "$OUT/stranger" --web "$STAGE" > "$OUT/build3.log" 2>&1
check "a build refuses a folder that is not a site build" "$?" 1

echo "── a sitemap, when the site knows its address"
python3 - "$SITE/site.json" <<'PYX'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['url']='https://example.github.io'; d['repository']='https://github.com/example/site'; json.dump(d, open(p,'w'), indent=2)
PYX
"$APP" --site-build "$SITE" --web "$STAGE" > "$OUT/build-sitemap.log" 2>&1
check "the manifest names the repository for the History link" "$(json '["repository"]' < "$DIST/manifest.json")" https://github.com/example/site
check "sitemap.xml lists the pages" "$(grep -c '<loc>https://example.github.io/publishing/</loc>' "$DIST/sitemap.xml")" 1
check "the home page is the root" "$(grep -c '<loc>https://example.github.io/</loc>' "$DIST/sitemap.xml")" 1
check "robots.txt points at it" "$(grep -c 'Sitemap: https://example.github.io/sitemap.xml' "$DIST/robots.txt")" 1
"$APP" --site-build "$SITE" --out "$OUT/project2/demo" --web "$STAGE" --base /demo/ > "$OUT/build-sitemap2.log" 2>&1
check "a project site's sitemap keeps the base once" "$(grep -c '<loc>https://example.github.io/demo/about/</loc>' "$OUT/project2/demo/sitemap.xml")" 1

echo "── a project site under /demo/"
"$APP" --site-build "$SITE" --out "$OUT/project/demo" --web "$STAGE" --base /demo/ > "$OUT/build4.log" 2>&1
check "build with --base exits 0" "$?" 0
check "the base is in the shell page" "$(grep -c '<base href="/demo/">' "$OUT/project/demo/about/index.html")" 1
check "the app is told the base" "$(grep -c "args: \['--site', '/demo/'\]" "$OUT/project/demo/about/index.html")" 1
check "the manifest routes under the base" "$(json '["base"]' < "$OUT/project/demo/manifest.json")" /demo/

echo "── an edit, as the native app's Save writes it, then a rebuild"
"$APP" --page-json "$REPO/apps/OfficeApp/Tests/OfficeAppTests/Fixtures/word-boringcrypto.docx" "$SITE/pages/about.json" 2>/dev/null \
    || printf '%s' '{}' > "$SITE/pages/about.json"
"$APP" --site-build "$SITE" --web "$STAGE" > "$OUT/build5.log" 2>&1
check "rebuild after the edit exits 0" "$?" 0
check "the search index follows the edit" "$(python3 -c "import json; d=json.load(open('$OUT/repo/docs/search.json')); print([e for e in d if e['slug']=='about'][0]['text'][:5] != 'Pages')")" True

echo "── import: a .docx becomes a page (what the Import button runs)"
SLUG="$("$APP" --site-import "$SITE" "$REPO/apps/OfficeApp/Tests/OfficeAppTests/Fixtures/word-boringcrypto.docx" --title "Imported policy" --under getting-started 2>"$OUT/import.log")"
check "site-import prints the new page's slug" "$SLUG" imported-policy
check "the page file is there with its page setup" "$(json '["pageSetup"]["width"]' < "$SITE/pages/imported-policy.json" 2>/dev/null)" 612
check "and it sits under its parent in site.json" "$(json '["pages"][1]["children"][-1]["slug"]' < "$SITE/site.json")" imported-policy
SLUG2="$("$APP" --site-import "$SITE" "$REPO/apps/OfficeApp/Tests/OfficeAppTests/Fixtures/word-boringcrypto.docx" --title "Imported policy" 2>/dev/null)"
check "a second page of the same title gets its own slug" "$SLUG2" imported-policy-2

echo "── move: a page one place among its siblings (the Move up/down buttons)"
check "move down" "$("$APP" --site-move "$SITE" index down 2>/dev/null)" moved
check "and the order follows" "$(json '["pages"][1]["slug"]' < "$SITE/site.json")" index
check "a page at the end stays" "$("$APP" --site-move "$SITE" imported-policy-2 down 2>/dev/null)" "already at the end"
"$APP" --site-move "$SITE" index up >/dev/null 2>&1

echo "── publish: build, commit, push to a bare remote (what the Publish button runs)"
PUB="$OUT/pub"; REMOTE="$OUT/remote.git"
cp -R "$REPO/examples/site" "$PUB"
git init -q --bare "$REMOTE"
( cd "$PUB" && git init -q && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -q -m "site" && git remote add origin "$REMOTE" && git push -q -u origin HEAD ) 2>"$OUT/git.log"
check "the sample repo is on its remote" "$?" 0
printf '%s' '{}' > "$PUB/pages/about.json"
"$APP" --site-publish "$PUB" --web "$STAGE" -m "about, emptied" > "$OUT/publish.log" 2>&1
check "site-publish exits 0" "$?" 0
sed 's/^/        /' "$OUT/publish.log"
check "the remote has the build" "$(git -C "$REMOTE" ls-tree -r HEAD --name-only | grep -c '^docs/manifest.json$')" 1
check "and the edited page" "$(git -C "$REMOTE" show HEAD:pages/about.json)" '{}'
check "under the message given" "$(git -C "$REMOTE" log -1 --format=%s)" 'about, emptied'
"$APP" --site-publish "$PUB" --web "$STAGE" -m "nothing new" > "$OUT/publish2.log" 2>&1
check "a publish with nothing to commit still exits 0" "$?" 0

echo
if [ $fails -eq 0 ]; then echo "site-build: all passed"; else echo "site-build: $fails failed"; fi
[ $fails -eq 0 ]
